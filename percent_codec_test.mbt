// percent_codec_test.mbt — RFC 8187 percent-encoding and decoding.

test "percent_decode_bytes decodes mixed input" {
  let bytes = @utf8.encode("a%20b%2Fc")
  let result = percent_decode_bytes(bytes, 0, bytes.length())
  match result {
    Ok(out) => {
      let sb = StringBuilder()
      for b in out {
        sb.write_char(b.to_char())
      }
      inspect(sb.to_string(), content="a b/c")
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "percent_decode_bytes decodes utf-8 octets" {
  let bytes = @utf8.encode("%C3%A9")
  match percent_decode_bytes(bytes, 0, bytes.length()) {
    Ok(out) => {
      let raw = Bytes::from_array(out)
      let value = @utf8.decode(raw.view(start=0, end=raw.length()))
      inspect(value, content="é")
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "percent_decode_bytes handles a bounded range" {
  let bytes = @utf8.encode("x%20y%20z")
  match percent_decode_bytes(bytes, 1, 8) {
    Ok(out) => {
      let sb = StringBuilder()
      for b in out {
        sb.write_char(b.to_char())
      }
      inspect(sb.to_string(), content=" y ")
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "percent_decode_bytes rejects a lone percent" {
  let bytes = @utf8.encode("50%")
  match percent_decode_bytes(bytes, 0, bytes.length()) {
    Ok(_) => assert_true(false, msg="expected an error")
    Err(e) => {
      inspect(e.kind().to_string(), content="InvalidPercentEncoding")
      inspect(e.offset(), content="2")
    }
  }
}

test "percent_decode_bytes rejects non-hex escape" {
  let bytes = @utf8.encode("%2G")
  match percent_decode_bytes(bytes, 0, bytes.length()) {
    Ok(_) => assert_true(false, msg="expected an error")
    Err(e) => inspect(e.kind().to_string(), content="InvalidPercentEncoding")
  }
}

test "percent_decode_bytes rejects a truncated escape at the range end" {
  let bytes = @utf8.encode("%2")
  match percent_decode_bytes(bytes, 0, bytes.length()) {
    Ok(_) => assert_true(false, msg="expected an error")
    Err(e) => inspect(e.kind().to_string(), content="InvalidPercentEncoding")
  }
}

test "percent_decode_string requires valid UTF-8 after decoding" {
  match percent_decode_string("a%20b") {
    Ok(v) => inspect(v, content="a b")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
  // 0xFF is not valid UTF-8.
  match percent_decode_string("%FF") {
    Ok(_) => assert_true(false, msg="expected an error")
    Err(e) => inspect(e.kind().to_string(), content="InvalidUtf8")
  }
  match percent_decode_string("caf%C3%A9") {
    Ok(v) => inspect(v, content="café")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "percent_encode_attr_value keeps attr-chars and encodes the rest" {
  inspect(percent_encode_attr_value("abc"), content="abc")
  inspect(percent_encode_attr_value("a b"), content="a%20b")
  inspect(percent_encode_attr_value("café"), content="caf%C3%A9")
  inspect(percent_encode_attr_value("a%b"), content="a%25b")
  inspect(percent_encode_attr_value("a.b-c_d"), content="a.b-c_d")
}

test "percent_encode_attr_value uses uppercase hex" {
  let encoded = percent_encode_attr_value("中文")
  // '中' encodes as %E4%B8%AD in UTF-8.
  inspect(encoded, content="%E4%B8%AD%E6%96%87")
}

test "percent_encode is the inverse of percent_decode" {
  let rng = prng(301)
  let failures : Array[String] = []
  for _i = 0; _i < 300; _i = _i + 1 {
    let value = random_unicode_name(rng, 12)
    let encoded = percent_encode_attr_value(value)
    match percent_decode_string(encoded) {
      Ok(decoded) =>
        if decoded != value {
          failures.push("round-trip mismatch for \{value}")
        }
      Err(e) => failures.push("decode error for \{encoded}: \{e.to_display()}")
    }
  }
  assert_true(failures.length() == 0, msg="failures: \{show_strings(failures)}")
}

test "has_percent_encoding detects escapes" {
  assert_true(has_percent_encoding("a%20b"))
  assert_true(has_percent_encoding("%"))
  assert_false(has_percent_encoding("abc"))
  assert_false(has_percent_encoding(""))
}
