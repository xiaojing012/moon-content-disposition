// percent_codec.mbt — RFC 3986 percent-encoding codec for RFC 8187 values.
//
// RFC 8187 extended values percent-encode every value byte that is not an
// `attr-char`. This module provides the two primitive operations used by
// the RFC 8187 parser and serializer: strict percent-decoding of a byte
// range, and deterministic percent-encoding of a UTF-8 string with
// uppercase hex digits. The decoding is deliberately strict: `%` must be
// followed by two hex digits, and the decoded bytes must be valid UTF-8
// (checked by the caller with the appropriate charset).

///|
/// Decodes the percent-encoded octets in `bytes[start, end)` into a raw
/// byte array. Every `%` must be followed by exactly two hex digits.
///
/// Errors: `PercentEncoding::InvalidPercentEncoding` (`%` not followed by
/// two hex digits, or a truncated escape at the end of the range).
pub fn percent_decode_bytes(
  bytes : Bytes,
  start : Int,
  end : Int
) -> Result[Array[Byte], DispositionError] {
  let out : Array[Byte] = []
  let mut i = start
  while i < end {
    let b = bytes[i]
    if b == 37 {
      // '%' followed by two hex digits, with explicit bounds checks so a
      // truncated escape at the end of the range is reported, not read
      // out of bounds.
      let h1 = if i + 1 < end { bytes[i + 1] } else { b'\x00' }
      let h2 = if i + 2 < end { bytes[i + 2] } else { b'\x00' }
      let v1 = hex_value(h1)
      let v2 = hex_value(h2)
      if i + 2 < end && v1 >= 0 && v2 >= 0 {
        out.push((v1 * 16 + v2).to_byte())
        i = i + 3
      } else {
        return Err(
          disposition_error_at(
            PercentEncoding,
            InvalidPercentEncoding,
            i,
            "expected '%' followed by two hex digits",
          ),
        )
      }
    } else {
      out.push(b)
      i = i + 1
    }
  }
  Ok(out)
}

///|
/// Percent-encodes a string for use as an RFC 8187 value. The string is
/// UTF-8 encoded; every byte that is not an `attr-char` is percent-encoded
/// with uppercase hex digits. The result is deterministic.
pub fn percent_encode_attr_value(value : String) -> String {
  let bytes = @utf8.encode(value)
  let sb = StringBuilder()
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
/// Percent-decodes a whole string and validates the decoded bytes as UTF-8.
///
/// Errors: `PercentEncoding::InvalidPercentEncoding` and
/// `PercentEncoding::InvalidUtf8`.
pub fn percent_decode_string(input : String) -> Result[String, DispositionError] {
  let bytes = @utf8.encode(input)
  let raw = match percent_decode_bytes(bytes, 0, bytes.length()) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  let encoded = Bytes::from_array(raw)
  let value = try {
    @utf8.decode(encoded.view(start=0, end=encoded.length()))
  } catch {
    _ =>
      return Err(
        disposition_error(PercentEncoding, InvalidUtf8, "decoded bytes are not valid UTF-8"),
      )
  }
  Ok(value)
}

///|
/// Whether a string contains any percent-encoded octets (used by tests).
pub fn has_percent_encoding(value : String) -> Bool {
  value.contains("%")
}
