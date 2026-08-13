// serializer.mbt — Deterministic serialisation and canonicalisation.
//
// Serialising a `ContentDisposition` back to a header field value is
// deliberately deterministic:
//
//   - the disposition type is emitted in canonical lowercase
//     (`inline` / `attachment` / an extension token lower-cased);
//   - every parameter name is emitted in canonical lowercase
//     (parameter names are case-insensitive, RFC 6266 Section 4.2);
//   - parameters keep their model order;
//   - token values are emitted unquoted when they are valid tokens, quoted
//     values through `serialize_quoted_string`, and extended values through
//     `serialize_extended_value` (which re-encodes deterministically with
//     uppercase hex).
//
// `canonicalize_content_disposition` is the user-facing normaliser: it
// parses a header value and re-serialises it with one additional rule — when
// both `filename` and `filename*` are present, `filename` (the fallback)
// precedes `filename*` (the primary). Canonicalisation is idempotent:
// `canonicalize(canonicalize(x)) == canonicalize(x)`.

///|
/// Serialises a `ContentDisposition` to a header field value, deterministically.
///
/// The disposition type and every parameter name are emitted in canonical
/// lowercase; parameters keep their model order. Token values must be valid
/// tokens; a hand-built model with an invalid token value is rejected rather
/// than silently re-quoted.
///
/// Errors: `Serialization::UnexpectedCharacter` (a token value is not a
/// valid token).
pub fn serialize_content_disposition(cd : ContentDisposition) -> Result[String, DispositionError] {
  let sb = StringBuilder()
  sb.write_string(cd.disposition_type().to_lower_name())
  for p in cd.parameters() {
    match check_param_name_token(p) {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    sb.write_string("; ")
    sb.write_string(p.name().to_lower())
    sb.write_string("=")
    match p.value() {
      Token(v) => {
        if !can_be_token(v) {
          return Err(
            disposition_error(
              Serialization,
              UnexpectedCharacter,
              "token value is not a valid token: \{truncate_for_error(v)}",
            ),
          )
        }
        sb.write_string(v)
      }
      Quoted(v) => sb.write_string(serialize_quoted_string(v))
      Extended(ev) => sb.write_string(serialize_extended_value(ev))
    }
  }
  Ok(sb.to_string())
}

///|
/// Serialises a `ContentDisposition` preserving the original casing of the
/// disposition type and parameter names. Used by round-trip tests to check
/// that parsing preserves information. Not recommended for output: use
/// `serialize_content_disposition` for canonical output.
pub fn serialize_content_disposition_preserve_case(
  cd : ContentDisposition
) -> Result[String, DispositionError] {
  let sb = StringBuilder()
  match cd.raw_disposition_type() {
    Some(raw) => sb.write_string(raw)
    None =>
      match cd.disposition_type() {
        Inline => sb.write_string("inline")
        Attachment => sb.write_string("attachment")
        Extension(name) => sb.write_string(name)
      }
  }
  for p in cd.parameters() {
    match check_param_name_token(p) {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    sb.write_string("; ")
    sb.write_string(p.name())
    sb.write_string("=")
    match p.value() {
      Token(v) => {
        if !can_be_token(v) {
          return Err(
            disposition_error(
              Serialization,
              UnexpectedCharacter,
              "token value is not a valid token: \{truncate_for_error(v)}",
            ),
          )
        }
        sb.write_string(v)
      }
      Quoted(v) => sb.write_string(serialize_quoted_string(v))
      Extended(ev) => sb.write_string(serialize_extended_value(ev))
    }
  }
  Ok(sb.to_string())
}

// Validates a parameter name for serialisation, using the `Token` stage.
fn check_param_name_token(p : DispositionParameter) -> Result[Unit, DispositionError] {
  if !validate_token(p.name()) {
    return Err(
      disposition_error(
        Token,
        InvalidParameterName,
        "parameter name is not a valid token: \{truncate_for_error(p.name())}",
      ),
    )
  }
  Ok(())
}

///|
/// Parses and re-serialises a Content-Disposition header value into a
/// canonical form. The canonical form lower-cases the disposition type and
/// every parameter name, preserves parameter order except that a plain
/// `filename` parameter is emitted before a `filename*` parameter when both
/// are present, and re-encodes values deterministically. The operation is
/// idempotent: canonicalising the canonical form is a no-op.
///
/// Errors: any error that `parse_content_disposition` can raise.
pub fn canonicalize_content_disposition(input : String) -> Result[String, DispositionError] {
  let cd = match parse_content_disposition(input) {
    Ok(c) => c
    Err(e) => return Err(e)
  }
  let sb = StringBuilder()
  sb.write_string(cd.disposition_type().to_lower_name())
  for p in canonical_param_order(cd) {
    match check_param_name_token(p) {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    sb.write_string("; ")
    sb.write_string(p.name().to_lower())
    sb.write_string("=")
    match p.value() {
      Token(v) => {
        // A parsed token is always a valid token; this is defensive.
        if !can_be_token(v) {
          return Err(
            disposition_error(
              Serialization,
              UnexpectedCharacter,
              "token value is not a valid token: \{truncate_for_error(v)}",
            ),
          )
        }
        sb.write_string(v)
      }
      Quoted(v) => sb.write_string(serialize_quoted_string(v))
      Extended(ev) => sb.write_string(serialize_extended_value(ev))
    }
  }
  Ok(sb.to_string())
}

///|
/// The canonical parameter order: input order, except that every `filename*`
/// parameter is delayed until after the first plain `filename` parameter, so
/// that the fallback name precedes the primary name.
fn canonical_param_order(cd : ContentDisposition) -> Array[DispositionParameter] {
  let out : Array[DispositionParameter] = []
  let mut deferred : Array[DispositionParameter] = []
  let mut saw_filename = false
  for p in cd.parameters() {
    if p.name().equal_ignore_ascii_case("filename*") {
      if saw_filename {
        out.push(p)
      } else {
        deferred.push(p)
      }
    } else {
      out.push(p)
      if p.name().equal_ignore_ascii_case("filename") {
        saw_filename = true
        for d in deferred {
          out.push(d)
        }
        deferred = []
      }
    }
  }
  for d in deferred {
    out.push(d)
  }
  out
}

// A bounded excerpt of a value for an error message.
fn truncate_for_error(value : String) -> String {
  if value.char_length() > 40 {
    value[:40].to_owned() + "..."
  } else {
    value
  }
}
