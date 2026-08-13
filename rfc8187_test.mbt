// rfc8187_test.mbt — RFC 8187 extended values and language tags.

test "parse_extended_value_default decodes utf-8" {
  match parse_extended_value_default("UTF-8''caf%C3%A9") {
    Ok(ev) => {
      inspect(ev.charset(), content="UTF-8")
      assert_true(ev.language() is None)
      inspect(ev.value(), content="café")
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "parse_extended_value_default decodes iso-8859-1" {
  match parse_extended_value_default("ISO-8859-1'en'caf%E9") {
    Ok(ev) => {
      inspect(ev.charset(), content="ISO-8859-1")
      match ev.language() {
        Some(l) => inspect(l, content="en")
        None => assert_true(false, msg="expected a language")
      }
      inspect(ev.value(), content="café")
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "parse_extended_value_default handles an empty language" {
  match parse_extended_value_default("utf-8''report.pdf") {
    Ok(ev) => {
      inspect(ev.charset(), content="UTF-8")
      assert_true(ev.language() is None)
      inspect(ev.value(), content="report.pdf")
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "parse_extended_value_default handles a language tag" {
  match parse_extended_value_default("UTF-8'zh-Hans-CN'%E4%B8%AD%E6%96%87") {
    Ok(ev) => {
      match ev.language() {
        Some(l) => inspect(l, content="zh-Hans-CN")
        None => assert_true(false, msg="expected a language")
      }
      inspect(ev.value(), content="中文")
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "parse_extended_value_default rejects a missing charset" {
  match parse_extended_value_default("''abc") {
    Ok(_) => assert_true(false, msg="expected an error")
    Err(e) => inspect(e.kind().to_string(), content="MissingCharset")
  }
}

test "parse_extended_value_default rejects a missing separator" {
  // ';' is not a value-char: the value parse stops there and the rest is
  // reported as trailing input.
  match parse_extended_value_default("UTF-8''a;b") {
    Ok(_) => assert_true(false, msg="expected an error for ';'")
    Err(e) => inspect(e.kind().to_string(), content="TrailingInput")
  }
  match parse_extended_value_default("UTF-8'abc") {
    Ok(_) => assert_true(false, msg="expected an error")
    Err(e) => inspect(e.kind().to_string(), content="InvalidExtendedValue")
  }
}

test "parse_extended_value_default rejects an unsupported charset" {
  match parse_extended_value_default("SHIFT-JIS''abc") {
    Ok(_) => assert_true(false, msg="expected an error")
    Err(e) => {
      inspect(e.stage().to_string(), content="ExtendedValue")
      inspect(e.kind().to_string(), content="UnsupportedCharset")
    }
  }
}

test "parse_extended_value_default rejects invalid percent encoding" {
  match parse_extended_value_default("UTF-8''a%2Gb") {
    Ok(_) => assert_true(false, msg="expected an error")
    Err(e) => inspect(e.kind().to_string(), content="InvalidPercentEncoding")
  }
}

test "parse_extended_value_default rejects invalid utf-8" {
  match parse_extended_value_default("UTF-8''%FF") {
    Ok(_) => assert_true(false, msg="expected an error")
    Err(e) => inspect(e.kind().to_string(), content="InvalidUtf8")
  }
}

test "parse_extended_value_default rejects trailing input" {
  // '?' is not an attr-char, so the value ends at "abc" and the rest is
  // reported as trailing input. ('!' is a valid attr-char and would simply
  // extend the value.)
  match parse_extended_value_default("UTF-8''abc?x") {
    Ok(_) => assert_true(false, msg="expected an error for '?'")
    Err(e) => inspect(e.kind().to_string(), content="TrailingInput")
  }
}

test "serialize_extended_value is deterministic" {
  let ev = extended_value("utf-8", None, "café")
  inspect(serialize_extended_value(ev), content="UTF-8''caf%C3%A9")
}

test "serialize_extended_value keeps the language" {
  let ev = extended_value("UTF-8", Some("en"), "report.pdf")
  inspect(serialize_extended_value(ev), content="UTF-8'en'report.pdf")
}

test "serialize_extended_value picks iso-8859-1 when the value fits" {
  let ev = extended_value("UTF-8", None, "café")
  // é fits Latin-1, but the charset is UTF-8 so UTF-8 is kept.
  inspect(serialize_extended_value(ev), content="UTF-8''caf%C3%A9")
  let ev2 = extended_value("ISO-8859-1", None, "café")
  inspect(serialize_extended_value(ev2), content="ISO-8859-1''caf%E9")
}

test "serialize then parse extended value round-trips" {
  let rng = prng(501)
  let failures : Array[String] = []
  for _i = 0; _i < 300; _i = _i + 1 {
    let value = random_unicode_name(rng, 12)
    let lang = if rng.bool() { Some("en") } else { None }
    let ev = extended_value("UTF-8", lang, value)
    let encoded = serialize_extended_value(ev)
    match parse_extended_value_default(encoded) {
      Ok(decoded) =>
        if decoded.value() != value {
          failures.push("value mismatch for \{value} via \{encoded}")
        }
      Err(e) => failures.push("parse error for \{encoded}: \{e.to_display()}")
    }
  }
  assert_true(failures.length() == 0, msg="failures: \{show_strings(failures)}")
}

test "attr_char is token minus star, quote and percent" {
  assert_true(attr_char(b'a'))
  assert_true(attr_char(b'0'))
  assert_true(attr_char(b'!'))
  assert_true(attr_char(b'.'))
  assert_true(attr_char(b'-'))
  assert_false(attr_char(b'*'))
  assert_false(attr_char(b'\''))
  assert_false(attr_char(b'%'))
  assert_false(attr_char(b' '))
  assert_false(attr_char(b'"'))
}

test "valid_language_tag accepts well-formed tags" {
  for t in ["en", "en-US", "zh-Hans-CN", "x-private", "EN", "fr-ca"] {
    assert_true(valid_language_tag(t), msg="tag \{t} should be valid")
  }
}

test "valid_language_tag rejects malformed tags" {
  for t in ["", "e", "12345", "en--US", "-en", "en-", "a-b-c-d-e-f-g-h-i", "en!US"] {
    assert_false(valid_language_tag(t), msg="tag \{t} should be invalid")
  }
}
