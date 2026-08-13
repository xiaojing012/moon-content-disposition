// quoted_string.mbt — RFC 7230 quoted-string parsing and serialisation.
//
// The RFC 6266 `value` rule uses the RFC 7230 quoted-string form: a byte
// sequence delimited by DQUOTE that may contain any `qdtext` byte and any
// `quoted-pair` (`\` followed by a valid byte). Semicolons and equals signs
// inside a quoted-string are data, not delimiters — which is exactly why
// the scanner is a cursor and not `split`.

///|
/// Parses a quoted-string starting at the current scanner position (which
/// must be the opening DQUOTE). On success the cursor is positioned after
/// the closing DQUOTE. The returned string is the unquoted content with
/// quoted-pairs resolved (`\"` becomes `"`, `\\` becomes `\`).
///
/// Errors: `QuotedString::UnterminatedQuotedString` (no closing DQUOTE),
/// `QuotedString::InvalidQuotedPair` (backslash not followed by a valid
/// quoted-pair byte), `QuotedString::InvalidControlCharacter` (a control
/// character that is not HTAB inside the string), `Limit::LimitExceeded`
/// (the string is longer than `max_parameter_value_bytes`).
pub fn parse_quoted_string(
  cursor : Scanner,
  limits : Limits
) -> Result[String, DispositionError] {
  try {
    Ok(parse_quoted_string_inner(cursor, limits))
  } catch {
    e => Err(unwrap_disposition_error(e))
  }
}

fn parse_quoted_string_inner(cursor : Scanner, limits : Limits) -> String raise {
  if !cursor.consume_char(34) {
    raise disposition_error_at(
      QuotedString,
      UnexpectedCharacter,
      cursor.position(),
      "expected opening DQUOTE",
    )
  }
  let start = cursor.position()
  let sb = StringBuilder()
  let mut done = false
  while !done {
    if cursor.eof() {
      raise disposition_error_at(
        QuotedString,
        UnterminatedQuotedString,
        start,
        cursor.context_string(),
      )
    }
    let b = cursor.peek_byte().unwrap()
    if b == 34 {
      cursor.pos = cursor.pos + 1
      done = true
    } else if b == 92 {
      // backslash: quoted-pair
      let pair_pos = cursor.position()
      cursor.pos = cursor.pos + 1
      if cursor.eof() {
        raise disposition_error_at(
          QuotedString,
          InvalidQuotedPair,
          pair_pos,
          "dangling escape at end of quoted-string",
        )
      }
      let next = cursor.next_byte().unwrap()
      if !quoted_pair_ok(next) {
        raise disposition_error_at(
          QuotedString,
          InvalidQuotedPair,
          pair_pos,
          cursor.context_string(),
        )
      }
      sb.write_char(next.to_char())
    } else if qdtext_char(b) {
      // obs-text bytes (>= 0x80) can start a multi-byte UTF-8 sequence: our
      // strings are UTF-8, so decode the whole sequence when its continuation
      // bytes are present rather than emitting one Latin-1 character per byte.
      let p = cursor.pos
      if b.to_int() >= 128 {
        let seq_len = utf8_sequence_len(b)
        if seq_len > 1 && has_continuation_bytes(cursor, p, seq_len) {
          sb.write_string(cursor.take_string(p, p + seq_len))
          cursor.pos = p + seq_len
        } else {
          sb.write_char(b.to_char())
          cursor.pos = p + 1
        }
      } else {
        sb.write_char(b.to_char())
        cursor.pos = p + 1
      }
    } else if is_control_byte(b) {
      raise disposition_error_at(
        QuotedString,
        InvalidControlCharacter,
        cursor.position(),
        cursor.context_string(),
      )
    } else {
      raise disposition_error_at(
        QuotedString,
        UnexpectedCharacter,
        cursor.position(),
        cursor.context_string(),
      )
    }
    if cursor.position() - start > limits.max_parameter_value_bytes() {
      raise disposition_error_at(
        Limit,
        LimitExceeded,
        cursor.position(),
        "quoted-string exceeds max_parameter_value_bytes",
      )
    }
  }
  sb.to_string()
}

///|
/// Serialises a string as a quoted-string, deterministically. Only `"` and
/// `\` are escaped (with a backslash); every other character is emitted
/// as-is. The result always starts and ends with DQUOTE.
pub fn serialize_quoted_string(value : String) -> String {
  let sb = StringBuilder()
  sb.write_char('"')
  for ch in value {
    if ch == '"' || ch == '\\' {
      sb.write_char('\\')
    }
    sb.write_char(ch)
  }
  sb.write_char('"')
  sb.to_string()
}

// The number of bytes in the UTF-8 sequence a lead byte announces (RFC 3629),
// or 1 when the byte is not a valid lead byte.
fn utf8_sequence_len(lead : Byte) -> Int {
  let v = lead.to_int()
  if v >= 0xC2 && v <= 0xDF {
    2
  } else if v >= 0xE0 && v <= 0xEF {
    3
  } else if v >= 0xF0 && v <= 0xF4 {
    4
  } else {
    1
  }
}

// Whether the bytes following `start` (offsets 1..len-1) are UTF-8
// continuation bytes (0x80-0xBF). DQUOTE and backslash can never be
// continuation bytes, so this cannot run past a delimiter.
fn has_continuation_bytes(cursor : Scanner, start : Int, len : Int) -> Bool {
  for j = 1; j < len; j = j + 1 {
    match cursor.byte_at(start + j) {
      Some(b) if b.to_int() >= 128 && b.to_int() <= 191 => ()
      _ => return false
    }
  }
  true
}

///|
/// Whether a string can be emitted as an unquoted token (all bytes are
/// `tchar` and the string is non-empty). Used by the serializer to decide
/// between the token and quoted forms.
pub fn can_be_token(value : String) -> Bool {
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
/// Whether a string is free of characters that would be dangerous inside a
/// header value: NUL, CR, LF and other C0 controls. Used by the generator
/// before emitting a filename.
pub fn is_header_safe(value : String) -> Bool {
  let bytes = @utf8.encode(value)
  for i = 0; i < bytes.length(); i = i + 1 {
    if is_control_byte(bytes[i]) {
      return false
    }
  }
  true
}
