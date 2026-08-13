// rfc8187.mbt — RFC 8187 extended parameter values.
//
// RFC 8187 defines the `ext-value` microsyntax used by the `filename*`
// parameter (and any extension parameter whose name ends with `*`):
//
//     ext-value   = charset  "'" [ language ] "'" value-chars
//     charset     = "UTF-8" / mime-charsetc
//     language    = <Language-Tag, RFC 5646>
//     value-chars = *( pct-encoded / attr-char )
//     pct-encoded = "%" HEXDIG HEXDIG
//
// RFC 8187 Section 3 requires implementations to support the UTF-8
// charset. This library supports UTF-8 and ISO-8859-1 (see charset.mbt)
// and rejects every other charset with `UnsupportedCharset` rather than
// decoding it incorrectly. The decoded value is stored as a MoonBit
// String; the charset is stored in canonical form.

///|
/// Parses an extended value starting at the current scanner position. On
/// success the cursor is positioned immediately after the last value-char.
///
/// Errors: `ExtendedValue::MissingCharset` (no charset before the first
/// apostrophe), `ExtendedValue::InvalidCharset` (malformed charset),
/// `ExtendedValue::InvalidExtendedValue` (missing separator),
/// `ExtendedValue::InvalidLanguage`, `ExtendedValue::InvalidPercentEncoding`,
/// `ExtendedValue::InvalidUtf8`, `Charset::UnsupportedCharset`, and
/// `Limit::LimitExceeded`.
pub fn parse_extended_value(
  cursor : Scanner,
  limits : Limits
) -> Result[ExtendedValue, DispositionError] raise {
  let start = cursor.position()

  // charset: 1*mime-charsetc
  let (cs_start, cs_end) = cursor.consume_while(fn(b) { mime_charsetc(b) })
  if cs_end == cs_start {
    raise disposition_error_at(
      ExtendedValue,
      MissingCharset,
      start,
      "expected charset before the first apostrophe",
    )
  }
  if !cursor.consume_char(39) {
    raise disposition_error_at(
      ExtendedValue,
      InvalidCharset,
      cursor.position(),
      "expected apostrophe after charset",
    )
  }
  let charset_raw = cursor.take_string(cs_start, cs_end)

  // language: [ Language-Tag ]  (may be empty)
  let (lang_start, lang_end) = cursor.consume_while(fn(b) { language_subtag_char(b) })
  if !cursor.consume_char(39) {
    raise disposition_error_at(
      ExtendedValue,
      InvalidExtendedValue,
      cursor.position(),
      "expected apostrophe after language",
    )
  }
  let lang_raw = cursor.take_string(lang_start, lang_end)
  let language : String? = if lang_raw == "" {
    None
  } else {
    if !valid_language_tag(lang_raw) {
      raise disposition_error_at(
        ExtendedValue,
        InvalidLanguage,
        lang_start,
        "invalid Language-Tag: \{lang_raw}",
      )
    }
    Some(lang_raw)
  }

  // value-chars: *( pct-encoded / attr-char )
  // The limit applies to the value-chars payload, not to the charset and
  // language prefix, so a value of exactly max_extended_value_bytes bytes
  // is accepted regardless of how long the charset name is.
  let value_start = cursor.position()
  let value_bytes : Array[Byte] = []
  let mut done = false
  while !done {
    match cursor.peek_byte() {
      Some(b) if attr_char(b) => {
        value_bytes.push(b)
        cursor.pos = cursor.pos + 1
      }
      Some(b) if b == 37 => {
        // percent-encoded octet
        let pct_pos = cursor.position()
        cursor.pos = cursor.pos + 1
        match (cursor.peek_byte(), cursor.peek_at(1)) {
          (Some(h1), Some(h2)) if is_hexdigit(h1) && is_hexdigit(h2) => {
            value_bytes.push((hex_value(h1) * 16 + hex_value(h2)).to_byte())
            cursor.pos = cursor.pos + 2
          }
          _ =>
            raise disposition_error_at(
              ExtendedValue,
              InvalidPercentEncoding,
              pct_pos,
              "expected '%' followed by two hex digits",
            )
        }
      }
      _ => done = true
    }
    if cursor.position() - value_start > limits.max_extended_value_bytes() {
      raise disposition_error_at(
        Limit,
        LimitExceeded,
        cursor.position(),
        "extended value exceeds max_extended_value_bytes",
      )
    }
  }

  // charset support check + decode
  let charset = match canonical_charset(charset_raw) {
    Some(c) => c
    None =>
      raise disposition_error_at(
        ExtendedValue,
        UnsupportedCharset,
        cs_start,
        "unsupported charset: \{charset_raw} (supported: UTF-8, ISO-8859-1)",
      )
  }
  let encoded = Bytes::from_array(value_bytes)
  let decoded = match decode_bytes(charset, encoded) {
    Ok(v) => v
    Err(e) => raise e
  }
  Ok({ charset, language, value: decoded })
}

///|
/// Parses a complete extended value from a string (the value of a `*`
/// parameter, without the name or `=`).
pub fn parse_extended_value_string(
  input : String,
  limits : Limits
) -> Result[ExtendedValue, DispositionError] {
  try {
    let cursor = Scanner::new(input)
    let ev = unwrap_or_raise(parse_extended_value(cursor, limits))
    if !cursor.eof() {
      raise disposition_error_at(
        ExtendedValue,
        TrailingInput,
        cursor.position(),
        "trailing bytes after extended value",
      )
    }
    Ok(ev)
  } catch {
    e => Err(unwrap_disposition_error(e))
  }
}

///|
/// Parses a complete extended value from a string with default limits.
pub fn parse_extended_value_default(input : String) -> Result[ExtendedValue, DispositionError] {
  parse_extended_value_string(input, Limits::default())
}

///|
/// Serialises an extended value deterministically. The charset is emitted
/// in canonical form (`UTF-8`, or `ISO-8859-1` when the value is entirely
/// representable in Latin-1); the language is emitted when present; every
/// value byte outside `attr-char` is percent-encoded with uppercase hex
/// digits.
pub fn serialize_extended_value(ev : ExtendedValue) -> String {
  let effective = if ev.charset.equal_ignore_ascii_case("ISO-8859-1") &&
    fits_iso8859_1(ev.value) {
    "ISO-8859-1"
  } else {
    "UTF-8"
  }
  let bytes = match encode_to_bytes(effective, ev.value) {
    Ok(b) => b
    Err(_) => @utf8.encode(ev.value)
  }
  let sb = StringBuilder()
  sb.write_string(effective)
  sb.write_char('\'')
  match ev.language {
    Some(l) => sb.write_string(l)
    None => ()
  }
  sb.write_char('\'')
  for i = 0; i < bytes.length(); i = i + 1 {
    let b = bytes[i]
    if attr_char(b) {
      sb.write_char(b.to_char())
    } else {
      sb.write_char('%')
      sb.write_char(hex_char(b.to_int() >> 4))
      sb.write_char(hex_char(b.to_int() & 0xF))
    }
  }
  sb.to_string()
}

///|
/// RFC 8187 `mime-charsetc`.
fn mime_charsetc(b : Byte) -> Bool {
  is_alpha(b) || is_digit(b) || b == 33 || b == 35 || b == 36 || b == 37 ||
    b == 38 || b == 43 || b == 45 || b == 94 || b == 95 || b == 96 || b == 123 ||
    b == 125 || b == 126
}

///|
/// RFC 8187 `attr-char`: token except `*`, `'`, `%`.
pub fn attr_char(b : Byte) -> Bool {
  is_alpha(b) || is_digit(b) || b == 33 || b == 35 || b == 36 || b == 38 ||
    b == 43 || b == 45 || b == 46 || b == 94 || b == 95 || b == 96 || b == 124 ||
    b == 126
}

///|
/// Characters permitted inside a language tag run (RFC 5646: ALPHA / DIGIT
/// / `-`; structural validation happens separately).
fn language_subtag_char(b : Byte) -> Bool {
  is_alpha(b) || is_digit(b) || b == 45
}

///|
/// Validates an RFC 5646 Language-Tag. Implements the pragmatic subset
/// used by RFC 8187 recipients: one or more subtags separated by `-`; the
/// primary subtag is 2-8 letters (or the single letter `x` for private
/// use); each extended subtag is 1-8 alphanumeric characters.
pub fn valid_language_tag(tag : String) -> Bool {
  if tag.char_length() == 0 {
    return false
  }
  let bytes = @utf8.encode(tag)
  // split into subtags
  let subtags : Array[(Int, Int)] = []
  let mut i = 0
  let mut sub_start = 0
  while i <= bytes.length() {
    if i == bytes.length() || bytes[i] == 45 {
      subtags.push((sub_start, i))
      sub_start = i + 1
    }
    i = i + 1
  }
  if subtags.is_empty() {
    return false
  }
  let (fs, fe) = subtags[0]
  let flen = fe - fs
  let primary_ok = if flen == 1 {
    // RFC 5646 private use: the primary subtag is the single letter x/X
    // (e.g. "x-private").
    let b = bytes[fs]
    b == 120 || b == 88
  } else {
    flen >= 2 && flen <= 8 && all_alpha(bytes, fs, fe)
  }
  if !primary_ok {
    return false
  }
  for j = 1; j < subtags.length(); j = j + 1 {
    let (s, e) = subtags[j]
    let l = e - s
    if l < 1 || l > 8 {
      return false
    }
    // every extended subtag must be alphanumeric
    for k = s; k < e; k = k + 1 {
      if !(is_alpha(bytes[k]) || is_digit(bytes[k])) {
        return false
      }
    }
  }
  true
}

fn all_alpha(bytes : Bytes, start : Int, end : Int) -> Bool {
  for i = start; i < end; i = i + 1 {
    if !is_alpha(bytes[i]) {
      return false
    }
  }
  true
}
