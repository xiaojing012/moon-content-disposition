// quoted_string_test.mbt — RFC 7230 quoted-string parsing and serialising.

// Returns the error kind of a failed quoted-string parse, or "" on success.
fn quoted_error_kind(input : String) -> String {
  let s = Scanner::new(input)
  match parse_quoted_string(s, Limits::default()) {
    Ok(_) => ""
    Err(e) => e.kind().to_string()
  }
}

test "serialize_quoted_string wraps and escapes quote and backslash" {
  inspect(serialize_quoted_string("plain"), content="\"plain\"")
  inspect(serialize_quoted_string("a\"b"), content="\"a\\\"b\"")
  inspect(serialize_quoted_string("a\\b"), content="\"a\\\\b\"")
  inspect(serialize_quoted_string(""), content="\"\"")
  inspect(serialize_quoted_string("with space"), content="\"with space\"")
}

test "parse_quoted_string reads a simple value" {
  let s = Scanner::new("\"report.pdf\"")
  let result = parse_quoted_string(s, Limits::default())
  match result {
    Ok(v) => inspect(v, content="report.pdf")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "parse_quoted_string handles escaped quotes and backslashes" {
  let s = Scanner::new("\"a\\\"b\\\\c\"")
  let result = parse_quoted_string(s, Limits::default())
  match result {
    Ok(v) => inspect(v, content="a\"b\\c")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "parse_quoted_string accepts space, tab and obs-text" {
  let s = Scanner::new("\"a b\tc\"")
  match parse_quoted_string(s, Limits::default()) {
    Ok(v) => inspect(v, content="a b\tc")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "parse_quoted_string rejects a missing opening quote" {
  inspect(quoted_error_kind("noquote"), content="UnexpectedCharacter")
}

test "parse_quoted_string rejects an unterminated string" {
  inspect(quoted_error_kind("\"abc"), content="UnterminatedQuotedString")
}

test "parse_quoted_string rejects a control character inside" {
  inspect(quoted_error_kind("\"a\u{0000}b\""), content="InvalidControlCharacter")
}

test "parse_quoted_string rejects an invalid quoted-pair" {
  inspect(quoted_error_kind("\"a\\\u{0000}b\""), content="InvalidQuotedPair")
}

test "quoted-string round-trips through serialize" {
  let rng = prng(202)
  let failures : Array[String] = []
  for _i = 0; _i < 300; _i = _i + 1 {
    let value = random_string_from(rng, "abcXYZ 0123.,_-!@#%&()[]{}+=;'~\"\\", rng.below(20))
    let encoded = serialize_quoted_string(value)
    let s = Scanner::new(encoded)
    match parse_quoted_string(s, Limits::default()) {
      Ok(decoded) =>
        if decoded != value {
          failures.push("round-trip mismatch for \{value}")
        }
      Err(e) => failures.push("parse error for \{encoded}: \{e.to_display()}")
    }
  }
  assert_true(failures.length() == 0, msg="failures: \{show_strings(failures)}")
}

test "quoted-string round-trips non-ASCII values" {
  let rng = prng(203)
  let failures : Array[String] = []
  for _i = 0; _i < 100; _i = _i + 1 {
    let value = random_unicode_name(rng, 16)
    let encoded = serialize_quoted_string(value)
    let s = Scanner::new(encoded)
    match parse_quoted_string(s, Limits::default()) {
      Ok(decoded) =>
        if decoded != value {
          failures.push("round-trip mismatch for \{value}")
        }
      Err(e) => failures.push("parse error for \{encoded}: \{e.to_display()}")
    }
  }
  assert_true(failures.length() == 0, msg="failures: \{show_strings(failures)}")
}

test "can_be_token is true exactly for non-empty tchar strings" {
  assert_true(can_be_token("report.pdf"))
  assert_true(can_be_token("x"))
  assert_false(can_be_token(""))
  assert_false(can_be_token("with space"))
  assert_false(can_be_token("a=b"))
  assert_false(can_be_token("café"))
}

test "is_header_safe accepts printable text and rejects controls" {
  assert_true(is_header_safe("report.pdf"))
  assert_true(is_header_safe("café"))
  assert_false(is_header_safe("a\u{0000}b"))
  assert_false(is_header_safe("a\nb"))
  assert_false(is_header_safe("a\rb"))
}
