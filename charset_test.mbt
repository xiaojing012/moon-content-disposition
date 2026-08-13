// charset_test.mbt — Supported charsets: UTF-8 and ISO-8859-1.

test "is_supported_charset is case-insensitive" {
  assert_true(is_supported_charset("UTF-8"))
  assert_true(is_supported_charset("utf-8"))
  assert_true(is_supported_charset("Utf-8"))
  assert_true(is_supported_charset("ISO-8859-1"))
  assert_true(is_supported_charset("iso-8859-1"))
  assert_false(is_supported_charset("latin1"))
  assert_false(is_supported_charset("utf-16"))
  assert_false(is_supported_charset(""))
}

test "canonical_charset normalises supported names" {
  match canonical_charset("utf-8") {
    Some(c) => inspect(c, content="UTF-8")
    None => assert_true(false, msg="utf-8 should be canonicalised")
  }
  match canonical_charset("iso-8859-1") {
    Some(c) => inspect(c, content="ISO-8859-1")
    None => assert_true(false, msg="iso-8859-1 should be canonicalised")
  }
  assert_true(canonical_charset("shift-jis") is None)
}

test "decode_bytes utf-8" {
  match decode_bytes("UTF-8", @utf8.encode("café")) {
    Ok(v) => inspect(v, content="café")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "decode_bytes rejects invalid utf-8" {
  let bad = Bytes::from_array([0xC3])
  match decode_bytes("UTF-8", bad) {
    Ok(_) => assert_true(false, msg="expected an error")
    Err(e) => inspect(e.kind().to_string(), content="InvalidUtf8")
  }
}

test "decode_bytes iso-8859-1 maps bytes to code points" {
  // 0xE9 in Latin-1 is U+00E9 (é).
  let latin = Bytes::from_array([0x63, 0x61, 0x66, 0xE9])
  match decode_bytes("ISO-8859-1", latin) {
    Ok(v) => inspect(v, content="café")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "decode_bytes iso-8859-1 maps every byte 0x00-0xFF" {
  let bytes : Array[Byte] = []
  for i = 0; i < 256; i = i + 1 {
    bytes.push(i.to_byte())
  }
  let raw = Bytes::from_array(bytes)
  match decode_bytes("iso-8859-1", raw) {
    Ok(v) => {
      let mut ok = true
      for ch in v {
        if ch.to_int() > 255 {
          ok = false
        }
      }
      assert_true(ok)
      inspect(v.char_length(), content="256")
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "decode_bytes rejects an unsupported charset" {
  match decode_bytes("shift-jis", @utf8.encode("x")) {
    Ok(_) => assert_true(false, msg="expected an error")
    Err(e) => {
      inspect(e.stage().to_string(), content="Charset")
      inspect(e.kind().to_string(), content="UnsupportedCharset")
    }
  }
}

test "encode_to_bytes utf-8 round-trips" {
  match encode_to_bytes("UTF-8", "café") {
    Ok(bytes) => {
      let value = @utf8.decode(bytes.view(start=0, end=bytes.length()))
      inspect(value, content="café")
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "encode_to_bytes iso-8859-1 for latin-1 values" {
  match encode_to_bytes("ISO-8859-1", "café") {
    Ok(bytes) => {
      // é is U+00E9, which fits in Latin-1.
      inspect(bytes.length(), content="4")
      match decode_bytes("ISO-8859-1", bytes) {
        Ok(v) => inspect(v, content="café")
        Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
      }
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "encode_to_bytes falls back to utf-8 for non-latin values" {
  match encode_to_bytes("ISO-8859-1", "中文") {
    Ok(bytes) => {
      let value = @utf8.decode(bytes.view(start=0, end=bytes.length()))
      inspect(value, content="中文")
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "encode_to_bytes rejects an unsupported charset" {
  match encode_to_bytes("utf-16", "x") {
    Ok(_) => assert_true(false, msg="expected an error")
    Err(e) => inspect(e.kind().to_string(), content="UnsupportedCharset")
  }
}

test "fits_iso8859_1" {
  assert_true(fits_iso8859_1("café"))
  assert_true(fits_iso8859_1(""))
  assert_true(fits_iso8859_1("ASCII"))
  assert_false(fits_iso8859_1("中文"))
  assert_false(fits_iso8859_1("π"))
}

test "decode then encode iso-8859-1 is identity for latin values" {
  let rng = prng(401)
  let failures : Array[String] = []
  for _i = 0; _i < 200; _i = _i + 1 {
    let value = random_string_from(rng, "abcXYZ0123 éàüçñ ßÿ", rng.below(10))
    if fits_iso8859_1(value) {
      match encode_to_bytes("ISO-8859-1", value) {
        Ok(bytes) =>
          match decode_bytes("ISO-8859-1", bytes) {
            Ok(decoded) =>
              if decoded != value {
                failures.push("round-trip mismatch for \{value}")
              }
            Err(e) => failures.push("decode error: \{e.to_display()}")
          }
        Err(e) => failures.push("encode error: \{e.to_display()}")
      }
    }
  }
  assert_true(failures.length() == 0, msg="failures: \{show_strings(failures)}")
}
