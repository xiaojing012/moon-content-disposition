// token.mbt — HTTP character predicates for moon-content-disposition.
//
// These byte predicates implement the exact ABNF character classes used by
// the RFC 6266 Content-Disposition grammar, which inherits the RFC 7230
// token rules and the RFC 5234 basic rules. They are deliberately not "any
// non-empty string is a token": separators, control characters, spaces and
// non-ASCII bytes are classified explicitly so that malformed input is
// rejected instead of being silently accepted.

///|
/// `ALPHA` — ASCII letters.
pub fn is_alpha(b : Byte) -> Bool {
  let v = b.to_int()
  (v >= 65 && v <= 90) || (v >= 97 && v <= 122)
}

///|
/// `DIGIT` — ASCII digits.
pub fn is_digit(b : Byte) -> Bool {
  let v = b.to_int()
  v >= 48 && v <= 57
}

///|
/// `HEXDIG` — ASCII hex digits.
pub fn is_hexdigit(b : Byte) -> Bool {
  is_digit(b) || {
    let v = b.to_int()
    (v >= 65 && v <= 70) || (v >= 97 && v <= 102)
  }
}

///|
/// RFC 7230 `tchar` — allowed token characters.
pub fn token_char(b : Byte) -> Bool {
  let v = b.to_int()
  (v >= 48 && v <= 57) || // DIGIT
    (v >= 65 && v <= 90) || // ALPHA upper
    (v >= 97 && v <= 122) || // ALPHA lower
    b == 33 || b == 35 || b == 36 || b == 37 || b == 38 || b == 39 || b == 42 ||
    b == 43 || b == 45 || b == 46 || b == 94 || b == 95 || b == 96 || b == 124 ||
    b == 126
}

///|
/// Alias for `token_char`, matching the RFC 7230 `tchar` definition.
pub fn is_token_char(b : Byte) -> Bool {
  token_char(b)
}

///|
/// Whether a byte is optional whitespace (SP / HTAB only). CR and LF are
/// never treated as whitespace here: a bare CR or LF inside a header value
/// is a security-relevant control character, not ignorable whitespace.
pub fn is_ows_byte(b : Byte) -> Bool {
  b == 32 || b == 9
}

///|
/// Whether a byte is a C0 control character (0x00-0x1F, including NUL, CR
/// and LF) or DEL (0x7F). These must never appear unquoted in a
/// Content-Disposition value and are stripped or rejected by the filename
/// policy.
pub fn is_control_byte(b : Byte) -> Bool {
  let v = b.to_int()
  v < 32 || v == 127
}

///|
/// Whether a byte is a path separator (`/` or `\`).
pub fn is_path_separator(b : Byte) -> Bool {
  b == 47 || b == 92
}

///|
/// HTTP obs-text: bytes 0x80-0xFF. Allowed inside quoted-strings and
/// quoted-pairs per RFC 7230; in compatible mode also tolerated inside
/// unquoted parameter values so that legacy non-ASCII headers can be read.
pub fn is_obs_text(b : Byte) -> Bool {
  b.to_int() >= 128
}

///|
/// RFC 7230 `qdtext`: HTAB / SP / `!` / `#`-`[` / `]`-`~` / obs-text.
/// Notably excludes `"` and `\` and control characters.
pub fn qdtext_char(b : Byte) -> Bool {
  let v = b.to_int()
  b == 9 || b == 32 || v == 33 || (v >= 35 && v <= 91) || (v >= 93 && v <= 126) ||
    is_obs_text(b)
}

///|
/// A valid quoted-pair second byte: `\` followed by HTAB / SP / VCHAR /
/// obs-text (RFC 7230).
pub fn quoted_pair_ok(b : Byte) -> Bool {
  let v = b.to_int()
  b == 9 || b == 32 || (v >= 33 && v <= 126) || is_obs_text(b)
}

///|
/// Validates that a whole string is a non-empty HTTP token: every byte is
/// a `tchar`.
pub fn validate_token(value : String) -> Bool {
  if value.char_length() == 0 {
    return false
  }
  let bytes = @utf8.encode(value)
  for i = 0; i < bytes.length(); i = i + 1 {
    if !token_char(bytes[i]) {
      return false
    }
  }
  true
}

///|
/// Whether a byte is one of the RFC 7230 `separators` (structural
/// punctuation). Used to decide whether an unquoted run ends at a
/// separator.
pub fn is_separator_byte(b : Byte) -> Bool {
  b == 40 || b == 41 || b == 60 || b == 62 || b == 64 || b == 44 || b == 59 ||
    b == 58 || b == 47 || b == 91 || b == 93 || b == 123 || b == 125 || b == 63 ||
    b == 61 || b == 34 || b == 92 || b == 32 || b == 9
}

///|
/// Numeric value of a hex digit byte, or `-1` for a non-hex byte.
pub fn hex_value(b : Byte) -> Int {
  let v = b.to_int()
  if v >= 48 && v <= 57 {
    v - 48
  } else if v >= 65 && v <= 70 {
    v - 55
  } else if v >= 97 && v <= 102 {
    v - 87
  } else {
    -1
  }
}

///|
/// Uppercase hex digit character for a nibble (0-15).
pub fn hex_char(nibble : Int) -> Char {
  let v = nibble & 0xF
  if v < 10 {
    (48 + v).to_char().unwrap()
  } else {
    (55 + v).to_char().unwrap()
  }
}
