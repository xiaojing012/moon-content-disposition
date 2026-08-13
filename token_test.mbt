// token_test.mbt — HTTP character predicates and token validation.

test "is_alpha covers ASCII letters only" {
  assert_true(is_alpha(b'A'))
  assert_true(is_alpha(b'z'))
  assert_false(is_alpha(b'0'))
  assert_false(is_alpha(b'-'))
  assert_false(is_alpha(b'_'))
  assert_false(is_alpha((0xE9).to_byte()))
}

test "is_digit covers ASCII digits only" {
  assert_true(is_digit(b'0'))
  assert_true(is_digit(b'9'))
  assert_false(is_digit(b'a'))
  assert_false(is_digit(b' '))
}

test "is_hexdigit covers hex digits both cases" {
  for ch in "0123456789abcdefABCDEF" {
    assert_true(is_hexdigit(ch.to_int().to_byte()))
  }
  assert_false(is_hexdigit(b'g'))
  assert_false(is_hexdigit(b'G'))
  assert_false(is_hexdigit(b'-'))
}

test "token_char covers every RFC 7230 tchar" {
  assert_true(token_char(b'!'))
  assert_true(token_char(b'#'))
  assert_true(token_char(b'$'))
  assert_true(token_char(b'%'))
  assert_true(token_char(b'&'))
  assert_true(token_char(b'\''))
  assert_true(token_char(b'*'))
  assert_true(token_char(b'+'))
  assert_true(token_char(b'-'))
  assert_true(token_char(b'.'))
  assert_true(token_char(b'^'))
  assert_true(token_char(b'_'))
  assert_true(token_char(b'`'))
  assert_true(token_char(b'|'))
  assert_true(token_char(b'~'))
  assert_true(token_char(b'0'))
  assert_true(token_char(b'Z'))
  assert_true(token_char(b'a'))
}

test "token_char rejects separators and controls" {
  for ch in "()<>@,;:\\\"/[]?={} \t" {
    assert_false(token_char(ch.to_int().to_byte()))
  }
  assert_false(token_char((0x00).to_byte()))
  assert_false(token_char(b'\n'))
  assert_false(token_char(b'\r'))
}

test "is_ows_byte accepts space and tab only" {
  assert_true(is_ows_byte(b' '))
  assert_true(is_ows_byte(b'\t'))
  assert_false(is_ows_byte(b'\n'))
  assert_false(is_ows_byte(b'\r'))
  assert_false(is_ows_byte(b'a'))
}

test "is_control_byte covers C0 and DEL" {
  assert_true(is_control_byte((0x00).to_byte()))
  assert_true(is_control_byte(b'\n'))
  assert_true(is_control_byte(b'\r'))
  assert_true(is_control_byte((0x1F).to_byte()))
  assert_true(is_control_byte((0x7F).to_byte()))
  assert_true(is_control_byte(b'\t'))
  assert_false(is_control_byte(b' '))
  assert_false(is_control_byte(b'a'))
  assert_false(is_control_byte((0x80).to_byte()))
}

test "is_path_separator covers forward and back slash" {
  assert_true(is_path_separator(b'/'))
  assert_true(is_path_separator(b'\\'))
  assert_false(is_path_separator(b'-'))
  assert_false(is_path_separator(b'.'))
}

test "is_obs_text covers 0x80-0xFF" {
  assert_true(is_obs_text((0x80).to_byte()))
  assert_true(is_obs_text((0xFF).to_byte()))
  assert_false(is_obs_text(b'a'))
  assert_false(is_obs_text((0x7F).to_byte()))
}

test "qdtext_char excludes quote, backslash and controls" {
  assert_true(qdtext_char(b'a'))
  assert_true(qdtext_char(b'!'))
  assert_true(qdtext_char((0x80).to_byte()))
  assert_true(qdtext_char(b' '))
  assert_true(qdtext_char(b'\t'))
  assert_false(qdtext_char(b'"'))
  assert_false(qdtext_char(b'\\'))
  assert_false(qdtext_char(b'\n'))
  assert_false(qdtext_char((0x00).to_byte()))
  assert_false(qdtext_char((0x7F).to_byte()))
}

test "quoted_pair_ok accepts VCHAR, SP, HTAB and obs-text" {
  assert_true(quoted_pair_ok(b'a'))
  assert_true(quoted_pair_ok(b' '))
  assert_true(quoted_pair_ok(b'\t'))
  assert_true(quoted_pair_ok((0x80).to_byte()))
  assert_false(quoted_pair_ok(b'\n'))
  assert_false(quoted_pair_ok((0x00).to_byte()))
}

test "validate_token accepts real tokens" {
  for t in ["abc", "report.pdf", "a.b-c_d", "X!", "x*y+z", "a~b`c", "!#$%&'"] {
    assert_true(validate_token(t), msg="token \{t} should validate")
  }
}

test "validate_token rejects empty, separated and non-ASCII" {
  assert_false(validate_token(""))
  assert_false(validate_token("a b"))
  assert_false(validate_token("a;b"))
  assert_false(validate_token("a=b"))
  assert_false(validate_token("a\"b"))
  assert_false(validate_token("café"))
  assert_false(validate_token("你好"))
}

test "is_separator_byte lists RFC 7230 separators" {
  for ch in "()<>@,;:\\\"/[]?={} \t" {
    assert_true(is_separator_byte(ch.to_int().to_byte()))
  }
  assert_false(is_separator_byte(b'a'))
  assert_false(is_separator_byte(b'#'))
  assert_false(is_separator_byte(b'-'))
}

test "hex_value maps hex digits and rejects the rest" {
  inspect(hex_value(b'0'), content="0")
  inspect(hex_value(b'9'), content="9")
  inspect(hex_value(b'A'), content="10")
  inspect(hex_value(b'F'), content="15")
  inspect(hex_value(b'a'), content="10")
  inspect(hex_value(b'f'), content="15")
  inspect(hex_value(b'g'), content="-1")
  inspect(hex_value(b'-'), content="-1")
}

test "hex_char produces uppercase hex" {
  inspect(hex_char(0).to_string(), content="0")
  inspect(hex_char(9).to_string(), content="9")
  inspect(hex_char(10).to_string(), content="A")
  inspect(hex_char(15).to_string(), content="F")
  // Out-of-range nibbles are masked to 4 bits.
  inspect(hex_char(16).to_string(), content="0")
  inspect(hex_char(0x1F).to_string(), content="F")
}

test "property: every random token validates" {
  let rng = prng(101)
  let failures : Array[String] = []
  for _i = 0; _i < 500; _i = _i + 1 {
    let t = random_token(rng, 24)
    if !validate_token(t) {
      failures.push(t)
    }
  }
  assert_true(failures.length() == 0, msg="invalid tokens: \{show_strings(failures)}")
}
