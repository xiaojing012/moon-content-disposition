// generator.mbt — Building Content-Disposition header values from a filename.
//
// Generating is the inverse of parsing: a caller has a filename (from their
// own data, not from a header) and wants a Content-Disposition value that
// preserves it. The generator:
//
//   - always emits the disposition type in canonical lowercase;
//   - emits `filename="..."` as a quoted-string (RFC 7230 escaping, never
//     bare tokens — quoting is the deterministic, lossless form);
//   - when the filename contains non-ASCII characters, additionally emits an
//     RFC 8187 `filename*=UTF-8'<lang>'<value-chars>` parameter (the
//     RFC 8187 Section 5 producer requirement);
//   - rejects CR, LF, NUL and other control characters outright (RFC 6266
//     Section 7 injection defence) rather than emitting them.
//
// ASCII fallback policy: this library deliberately does NOT transliterate
// non-ASCII filenames into ASCII approximations (`café` stays `café`, it is
// never emitted as `cafe`). When the filename contains non-ASCII, the plain
// `filename` parameter carries the original characters (quoted, obs-text
// bytes) and `filename*` carries the unambiguous UTF-8 encoding. This is the
// documented, honest fallback; see `docs/compatibility.md`.

///|
/// Options controlling one generation.
pub struct GenerateOptions {
  include_filename_star : Bool
  always_filename_star : Bool
  language : String?
}

///|
/// Default generation options: emit `filename*` when the filename contains
/// non-ASCII characters (RFC 8187 Section 5), no language tag.
pub fn GenerateOptions::default() -> GenerateOptions {
  { include_filename_star: true, always_filename_star: false, language: None }
}

///|
/// Whether the RFC 8187 `filename*` parameter is emitted at all.
pub fn GenerateOptions::include_filename_star(self : GenerateOptions) -> Bool {
  self.include_filename_star
}

///|
/// Whether `filename*` is emitted even for pure-ASCII filenames (default
/// false; it is emitted only when the filename contains non-ASCII).
pub fn GenerateOptions::always_filename_star(self : GenerateOptions) -> Bool {
  self.always_filename_star
}

///|
/// The RFC 5646 language tag attached to `filename*`, if any.
pub fn GenerateOptions::language(self : GenerateOptions) -> String? {
  self.language
}

///|
/// A copy of these options with the given language tag.
pub fn GenerateOptions::with_language(self : GenerateOptions, language : String?) -> GenerateOptions {
  { include_filename_star: self.include_filename_star, always_filename_star: self.always_filename_star, language }
}

///|
/// A copy of these options with `filename*` disabled.
pub fn GenerateOptions::without_filename_star(self : GenerateOptions) -> GenerateOptions {
  { include_filename_star: false, always_filename_star: false, language: self.language }
}

///|
/// Generates an `attachment` Content-Disposition value for a filename.
///
/// Errors: `QuotedString::InvalidControlCharacter` (the filename contains a
/// control character — CR/LF/NUL injection defence).
pub fn generate_attachment(filename : String) -> Result[String, DispositionError] {
  generate_content_disposition(Attachment, filename, GenerateOptions::default())
}

///|
/// Generates an `inline` Content-Disposition value for a filename.
///
/// Errors: `QuotedString::InvalidControlCharacter`.
pub fn generate_inline(filename : String) -> Result[String, DispositionError] {
  generate_content_disposition(Inline, filename, GenerateOptions::default())
}

///|
/// Generates an `attachment` Content-Disposition value with explicit options.
pub fn generate_attachment_with_options(
  filename : String,
  options : GenerateOptions
) -> Result[String, DispositionError] {
  generate_content_disposition(Attachment, filename, options)
}

///|
/// Generates an `inline` Content-Disposition value with explicit options.
pub fn generate_inline_with_options(
  filename : String,
  options : GenerateOptions
) -> Result[String, DispositionError] {
  generate_content_disposition(Inline, filename, options)
}

///|
/// Generates a Content-Disposition value for the given disposition type and
/// filename with explicit options.
///
/// Errors: `QuotedString::InvalidControlCharacter` (control character in the
/// filename) and `ExtendedValue::InvalidLanguage` (a language tag was given
/// but is not a valid RFC 5646 tag).
pub fn generate_content_disposition(
  disposition_type : DispositionType,
  filename : String,
  options : GenerateOptions
) -> Result[String, DispositionError] {
  // CR/LF/NUL injection defence: no control byte may reach the wire.
  let bytes = @utf8.encode(filename)
  for i = 0; i < bytes.length(); i = i + 1 {
    if is_control_byte(bytes[i]) {
      return Err(
        disposition_error(
          QuotedString,
          InvalidControlCharacter,
          "filename contains a control character (CR/LF/NUL injection is rejected)",
        ),
      )
    }
  }
  let has_non_ascii = has_non_ascii_bytes(filename)
  let emit_star = options.include_filename_star() &&
    (options.always_filename_star() || has_non_ascii)
  // Validate a provided language tag before emitting it.
  match options.language() {
    Some(lang) => {
      if emit_star && !valid_language_tag(lang) {
        return Err(
          disposition_error(ExtendedValue, InvalidLanguage, "invalid RFC 5646 language tag: \{lang}"),
        )
      }
    }
    None => ()
  }
  let sb = StringBuilder()
  sb.write_string(disposition_type.to_lower_name())
  sb.write_string("; filename=")
  sb.write_string(serialize_quoted_string(filename))
  if emit_star {
    sb.write_string("; filename*=")
    sb.write_string("UTF-8'")
    match options.language() {
      Some(lang) => sb.write_string(lang)
      None => ()
    }
    sb.write_string("'")
    sb.write_string(percent_encode_attr_value(filename))
  }
  Ok(sb.to_string())
}

// Whether a string contains any byte >= 0x80.
fn has_non_ascii_bytes(value : String) -> Bool {
  let bytes = @utf8.encode(value)
  for i = 0; i < bytes.length(); i = i + 1 {
    if bytes[i].to_int() >= 128 {
      return true
    }
  }
  false
}
