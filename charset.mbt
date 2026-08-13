// charset.mbt — RFC 8187 charset policy.
//
// RFC 8187 Section 2 requires producers to use the UTF-8 charset for
// extended parameter values. Recipients may encounter other charsets.
// Rather than guessing, this library supports exactly two charsets, both
// implemented correctly and tested explicitly:
//
//   - `UTF-8`       — the required producer charset; decoded strictly.
//   - `ISO-8859-1`  — the safest legacy charset to support; each byte maps
//     to the same Unicode code point (U+0080-U+00FF for the high half).
//
// Any other charset is rejected with
// `DispositionErrorKind::UnsupportedCharset`. There is deliberately no
// encoding sniffing and no "try UTF-8, then guess GBK" behaviour: an
// unsupported charset is reported, never guessed.

///|
/// Whether a charset name is supported (case-insensitive `UTF-8` or
/// `ISO-8859-1`).
pub fn is_supported_charset(charset : String) -> Bool {
  charset.equal_ignore_ascii_case("UTF-8") || charset.equal_ignore_ascii_case("ISO-8859-1")
}

///|
/// The canonical form of a supported charset name, or `None` for an
/// unsupported charset. The canonical form is what the model stores and
/// what the serializer emits.
pub fn canonical_charset(charset : String) -> String? {
  if charset.equal_ignore_ascii_case("UTF-8") {
    Some("UTF-8")
  } else if charset.equal_ignore_ascii_case("ISO-8859-1") {
    Some("ISO-8859-1")
  } else {
    None
  }
}

///|
/// Decodes a raw byte array using the given charset name. For `UTF-8` the
/// bytes must form valid UTF-8; for `ISO-8859-1` every byte maps to the
/// code point with the same value.
///
/// Errors: `Charset::UnsupportedCharset` (unknown charset) and
/// `Charset::InvalidUtf8` (bytes are not valid UTF-8).
pub fn decode_bytes(
  charset : String,
  bytes : Bytes
) -> Result[String, DispositionError] {
  if charset.equal_ignore_ascii_case("UTF-8") {
    let value = try {
      @utf8.decode(bytes.view(start=0, end=bytes.length()))
    } catch {
      _ =>
        return Err(
          disposition_error(Charset, InvalidUtf8, "percent-decoded bytes are not valid UTF-8"),
        )
    }
    Ok(value)
  } else if charset.equal_ignore_ascii_case("ISO-8859-1") {
    Ok(decode_iso8859_1(bytes))
  } else {
    Err(
      disposition_error(
        Charset,
        UnsupportedCharset,
        "unsupported charset: \{charset} (supported: UTF-8, ISO-8859-1)",
      ),
    )
  }
}

///|
/// Encodes a value string to raw bytes using the given charset name, for
/// serialisation. `UTF-8` always succeeds; `ISO-8859-1` succeeds only when
/// every code point in the value fits in Latin-1 (U+0000-U+00FF), otherwise
/// the encoder falls back to UTF-8 (a documented, deterministic
/// normalisation).
///
/// Errors: `Charset::UnsupportedCharset` (unknown charset).
pub fn encode_to_bytes(charset : String, value : String) -> Result[Bytes, DispositionError] {
  if charset.equal_ignore_ascii_case("UTF-8") {
    Ok(@utf8.encode(value))
  } else if charset.equal_ignore_ascii_case("ISO-8859-1") {
    match encode_iso8859_1(value) {
      Some(bytes) => Ok(bytes)
      None => Ok(@utf8.encode(value))
    }
  } else {
    Err(
      disposition_error(
        Charset,
        UnsupportedCharset,
        "unsupported charset: \{charset} (supported: UTF-8, ISO-8859-1)",
      ),
    )
  }
}

///|
/// Whether every code point of `value` can be represented in ISO-8859-1.
pub fn fits_iso8859_1(value : String) -> Bool {
  for ch in value {
    if ch.to_int() > 0xFF {
      return false
    }
  }
  true
}

// Decodes ISO-8859-1 bytes to a UTF-8 encoded MoonBit String.
fn decode_iso8859_1(bytes : Bytes) -> String {
  let out : Array[Byte] = []
  for i = 0; i < bytes.length(); i = i + 1 {
    let v = bytes[i].to_int()
    if v < 0x80 {
      out.push(bytes[i])
    } else {
      // Two-byte UTF-8 for U+0080-U+00FF. For 0x80-0xFF the lead byte is
      // always 0xC2 or 0xC3, never an overlong form.
      out.push((0xC0 | (v >> 6)).to_byte())
      out.push((0x80 | (v & 0x3F)).to_byte())
    }
  }
  let encoded = Bytes::from_array(out)
  // The constructed byte array is always valid UTF-8 (every 0x80-0xFF byte
  // maps to the two-byte sequence C2/C3 80-BF, never an overlong form), so
  // the raise is purely a type-correctness measure and cannot fire.
  let decoded = try {
    @utf8.decode(encoded.view(start=0, end=encoded.length()))
  } catch {
    _ => abort("internal error: ISO-8859-1 decoding produced invalid UTF-8")
  }
  decoded
}

// Encodes a value string to ISO-8859-1 bytes, or `None` when a code point
// is outside Latin-1.
fn encode_iso8859_1(value : String) -> Bytes? {
  let out : Array[Byte] = []
  for ch in value {
    let v = ch.to_int()
    if v > 0xFF {
      return None
    }
    out.push(v.to_byte())
  }
  Some(Bytes::from_array(out))
}
