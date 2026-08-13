// scanner.mbt — Byte-oriented cursor for moon-content-disposition.
//
// A Content-Disposition header value cannot be parsed with `split(";")`: a
// semicolon inside a quoted-string (or inside an RFC 8187 extended value)
// is not a structural separator. This module provides a single,
// bounds-checked cursor over the UTF-8 bytes of the input. Every operation
// is safe at any position; nothing here can index out of bounds or loop
// forever.
//
// Positions are UTF-8 byte offsets into the original input string.

///|
/// A bounds-checked byte cursor over an input string.
pub struct Scanner {
  bytes : Bytes
  len : Int
  mut pos : Int
}

///|
/// Creates a scanner for a Content-Disposition header field value.
pub fn Scanner::new(input : String) -> Scanner {
  let bytes = @utf8.encode(input)
  { bytes, len: bytes.length(), pos: 0 }
}

///|
/// The current position, as a UTF-8 byte offset.
pub fn Scanner::position(self : Scanner) -> Int {
  self.pos
}

///|
/// Whether the cursor is at (or past) the end of the input.
pub fn Scanner::eof(self : Scanner) -> Bool {
  self.pos >= self.len
}

///|
/// The number of bytes remaining from the current position.
pub fn Scanner::remaining(self : Scanner) -> Int {
  if self.len > self.pos {
    self.len - self.pos
  } else {
    0
  }
}

///|
/// The total length of the input in bytes.
pub fn Scanner::total_bytes(self : Scanner) -> Int {
  self.len
}

///|
/// The byte at the current position, or `None` at end of input.
pub fn Scanner::peek_byte(self : Scanner) -> Byte? {
  if self.pos >= self.len {
    None
  } else {
    Some(self.bytes[self.pos])
  }
}

///|
/// The byte at `pos + rel`, or `None` when out of bounds. `rel` may be
/// negative to look behind the current position.
pub fn Scanner::peek_at(self : Scanner, rel : Int) -> Byte? {
  let idx = self.pos + rel
  if idx < 0 || idx >= self.len {
    None
  } else {
    Some(self.bytes[idx])
  }
}

///|
/// The byte at an absolute offset, or `None` when out of bounds.
pub fn Scanner::byte_at(self : Scanner, idx : Int) -> Byte? {
  if idx < 0 || idx >= self.len {
    None
  } else {
    Some(self.bytes[idx])
  }
}

///|
/// Returns the current byte and advances the cursor by one. Returns `None`
/// at end of input (and does not advance).
pub fn Scanner::next_byte(self : Scanner) -> Byte? {
  if self.pos >= self.len {
    None
  } else {
    let b = self.bytes[self.pos]
    self.pos = self.pos + 1
    Some(b)
  }
}

///|
/// If the current byte equals `b`, advances and returns `true`.
pub fn Scanner::consume_char(self : Scanner, b : Byte) -> Bool {
  match self.peek_byte() {
    Some(c) if c == b => {
      self.pos = self.pos + 1
      true
    }
    _ => false
  }
}

///|
/// Skips optional whitespace (OWS): SP (0x20) and HTAB (0x09). CR and LF
/// are never skipped.
pub fn Scanner::skip_ows(self : Scanner) -> Unit {
  let mut done = false
  while !done {
    match self.peek_byte() {
      Some(b) if b == 32 || b == 9 => self.pos = self.pos + 1
      _ => done = true
    }
  }
}

///|
/// Whether the current byte is optional whitespace under this grammar.
pub fn Scanner::is_ows(self : Scanner) -> Bool {
  match self.peek_byte() {
    Some(b) => b == 32 || b == 9
    None => false
  }
}

///|
/// Moves the cursor to an absolute byte offset, clamping out-of-range
/// positions to the ends of the input.
pub fn Scanner::seek(self : Scanner, pos : Int) -> Unit {
  if pos < 0 {
    self.pos = 0
  } else if pos > self.len {
    self.pos = self.len
  } else {
    self.pos = pos
  }
}

///|
/// Consumes a run of bytes satisfying `pred` and returns the `(start, end)`
/// byte range of the run. The run may be empty.
pub fn Scanner::consume_while(self : Scanner, pred : (Byte) -> Bool) -> (Int, Int) {
  let start = self.pos
  let mut done = false
  while !done {
    match self.peek_byte() {
      Some(b) if pred(b) => self.pos = self.pos + 1
      _ => done = true
    }
  }
  (start, self.pos)
}

///|
/// Consumes a run of HTTP token characters and returns the `(start, end)`
/// byte range. The run may be empty.
pub fn Scanner::consume_token(self : Scanner) -> (Int, Int) {
  self.consume_while(fn(b) { token_char(b) })
}

///|
/// Consumes a run of `attr-char` / percent-encoded bytes and returns the
/// `(start, end)` byte range of the raw value-chars (before percent
/// decoding). The run may be empty. Used to locate the raw extent of an
/// RFC 8187 extended value.
pub fn Scanner::consume_value_chars(self : Scanner) -> (Int, Int) {
  let start = self.pos
  let mut done = false
  while !done {
    match self.peek_byte() {
      Some(b) if attr_char(b) || b == 37 => self.pos = self.pos + 1
      _ => done = true
    }
  }
  (start, self.pos)
}

///|
/// The index of the next occurrence of byte `b` at or after the current
/// position, or `None`.
pub fn Scanner::find_byte(self : Scanner, b : Byte) -> Int? {
  let mut i = self.pos
  while i < self.len {
    if self.bytes[i] == b {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
/// Decodes the byte range `[start, end)` back into a String. Valid UTF-8
/// is decoded normally; a range that is not valid UTF-8 is preserved
/// byte-for-byte so that quoting round-trips never lose data.
pub fn Scanner::take_string(self : Scanner, start : Int, end : Int) -> String {
  let hi = if end > self.len { self.len } else { end }
  let lo = if start < 0 { 0 } else { start }
  if hi <= lo {
    return ""
  }
  try {
    @utf8.decode(self.bytes.view(start=lo, end=hi))
  } catch {
    _ => self.bytes.view(start=lo, end=hi).to_owned().to_unchecked_string()
  }
}

///|
/// A short, bounded excerpt of the input around the current position, for
/// use in error context strings. Never longer than `max_context_bytes()`.
pub fn Scanner::context_string(self : Scanner) -> String {
  let window = max_context_bytes()
  let mut start = self.pos - 24
  if start < 0 {
    start = 0
  }
  let mut take = window - 8
  if take > self.len - start {
    take = self.len - start
  }
  if take < 0 {
    take = 0
  }
  let excerpt = self.take_string(start, start + take)
  let prefix = if start > 0 { "..." } else { "" }
  let suffix = if start + take < self.len { "..." } else { "" }
  prefix + excerpt + suffix
}

///|
/// An excerpt of the input around the current position using an explicit
/// context bound (from the active `Limits`).
pub fn Scanner::context_string_limited(self : Scanner, limit : Int) -> String {
  let window = if limit < 16 { 16 } else { limit }
  let mut start = self.pos - 24
  if start < 0 {
    start = 0
  }
  let mut take = window - 8
  if take > self.len - start {
    take = self.len - start
  }
  if take < 0 {
    take = 0
  }
  let excerpt = self.take_string(start, start + take)
  let prefix = if start > 0 { "..." } else { "" }
  let suffix = if start + take < self.len { "..." } else { "" }
  prefix + excerpt + suffix
}
