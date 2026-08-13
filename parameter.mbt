// parameter.mbt — Single disposition parameter parsing.
//
// RFC 6266 defines each disposition parameter as
//
//     disposition-parm = filename-parm / disp-ext-parm
//     filename-parm    = "filename" "=" value
//                      / "filename*" "=" ext-value
//     disp-ext-parm    = token "=" value
//                      / ext-token "=" ext-value
//
// A parameter name that ends with `*` (with a non-empty base name) carries
// an RFC 8187 extended value; every other parameter carries either a token
// or a quoted-string value. This module parses exactly one parameter,
// leaving the cursor positioned just after its value.

///|
/// Parses a single parameter starting at the current scanner position
/// (which must be the first byte of the parameter name). On success the
/// cursor is positioned after the parameter value. Compatible-mode
/// recoveries are recorded on the collector.
pub fn parse_parameter(
  cursor : Scanner,
  limits : Limits,
  mode : ParseMode,
  collector : ParseCollector
) -> Result[DispositionParameter, DispositionError] {
  try {
    Ok(parse_parameter_inner(cursor, limits, mode, collector))
  } catch {
    e => Err(unwrap_disposition_error(e))
  }
}

fn parse_parameter_inner(
  cursor : Scanner,
  limits : Limits,
  mode : ParseMode,
  collector : ParseCollector
) -> DispositionParameter raise {
  let name_start = cursor.position()
  let (ns, ne) = cursor.consume_token()
  if ne == ns {
    raise disposition_error_at(
      ParameterName,
      ExpectedToken,
      name_start,
      "expected a parameter name",
    )
  }
  if ne - ns > limits.max_parameter_name_bytes() {
    raise disposition_error_at(
      Limit,
      LimitExceeded,
      name_start,
      "parameter name exceeds max_parameter_name_bytes",
    )
  }
  let name = cursor.take_string(ns, ne)
  cursor.skip_ows()
  if !cursor.consume_char(61) {
    // '='
    raise disposition_error_at(
      ParameterName,
      MissingEquals,
      cursor.position(),
      "expected '=' after parameter name '\{name}'",
    )
  }
  cursor.skip_ows()
  let value = match parse_parameter_value(cursor, limits, mode, name, collector) {
    Ok(v) => v
    Err(e) => raise e
  }
  disposition_parameter(name, value)
}

// Parses the value half of a parameter, dispatching on the extended form.
fn parse_parameter_value(
  cursor : Scanner,
  limits : Limits,
  mode : ParseMode,
  name : String,
  collector : ParseCollector
) -> Result[ParameterValue, DispositionError] raise {
  if is_extended_param_name(name) {
    return parse_extended_value_param(cursor, limits, mode, collector)
  }
  // plain parameter value: token / quoted-string
  match cursor.peek_byte() {
    Some(b) if b == 34 => {
      // '"'
      let s = unwrap_or_raise(parse_quoted_string(cursor, limits))
      Ok(Quoted(s))
    }
    _ => {
      // unquoted run; compatible mode additionally tolerates obs-text
      // bytes for legacy non-ASCII unquoted values.
      let (vs, ve) = if mode == Compatible {
        cursor.consume_while(fn(b) { token_char(b) || is_obs_text(b) })
      } else {
        cursor.consume_token()
      }
      if ve == vs {
        if mode == Compatible {
          collector.record_recovery("empty-parameter-value")
          Ok(Quoted(""))
        } else {
          raise disposition_error_at(
            ParameterValue,
            MissingParameterValue,
            cursor.position(),
            "expected a parameter value after '='",
          )
        }
      } else {
        if ve - vs > limits.max_parameter_value_bytes() {
          raise disposition_error_at(
            Limit,
            LimitExceeded,
            vs,
            "parameter value exceeds max_parameter_value_bytes",
          )
        }
        let s = cursor.take_string(vs, ve)
        if mode == Compatible && range_has_obs_text(cursor, vs, ve) {
          collector.record_recovery("legacy-unquoted-non-ascii-value")
        }
        Ok(Token(s))
      }
    }
  }
}

// Parses the value half of a `*` parameter (an RFC 8187 extended value).
fn parse_extended_value_param(
  cursor : Scanner,
  limits : Limits,
  mode : ParseMode,
  collector : ParseCollector
) -> Result[ParameterValue, DispositionError] raise {
  match cursor.peek_byte() {
    Some(b) if b == 34 => {
      // '"'
      if mode == Strict {
        raise disposition_error_at(
          ExtendedValue,
          InvalidExtendedValue,
          cursor.position(),
          "an extended value must not be quoted (strict mode)",
        )
      }
      let content = unwrap_or_raise(parse_quoted_string(cursor, limits))
      collector.record_recovery("quoted-extended-value")
      let ev = match parse_extended_value_string(content, limits) {
        Ok(ev) => ev
        Err(e) => raise e
      }
      Ok(Extended(ev))
    }
    _ => {
      let ev = unwrap_or_raise(parse_extended_value(cursor, limits))
      Ok(Extended(ev))
    }
  }
}

///|
/// Whether a parameter name denotes an RFC 8187 extended value (a
/// non-empty base name followed by `*`).
pub fn is_extended_param_name(name : String) -> Bool {
  name.char_length() > 1 && name.has_suffix("*")
}

// Whether the byte range [start, end) of the cursor contains obs-text.
fn range_has_obs_text(cursor : Scanner, start : Int, end : Int) -> Bool {
  for i = start; i < end; i = i + 1 {
    match cursor.byte_at(i) {
      Some(b) if is_obs_text(b) => return true
      _ => ()
    }
  }
  false
}
