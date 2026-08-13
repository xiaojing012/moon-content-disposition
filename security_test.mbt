// security_test.mbt — RFC 6266 Section 7 concerns and injection defences.

test "CR and LF are never whitespace in a header value" {
  // A header value that carries a line break cannot smuggle a second header.
  expect_parse_error("attachment; filename=a\r", "Input", "TrailingInput")
  expect_parse_error("attachment; filename=a\n", "Input", "TrailingInput")
  expect_parse_error("attachment\r\nX-Evil: 1", "Input", "TrailingInput")
}

test "NUL is never accepted in a quoted value" {
  expect_parse_error("attachment; filename=\"a\u{0000}b\"", "QuotedString", "InvalidControlCharacter")
}

test "percent-encoded CR LF and NUL decode but are flagged and sanitised" {
  match parse_content_disposition("attachment; filename*=UTF-8''a%0A%0D%00b") {
    Ok(cd) => {
      match resolve_filename(cd) {
        Ok(sel) => {
          expect_same_strings(sel.warnings(), ["contains-control-character"])
          // Sanitisation removes the decoded control bytes.
          match sanitize_portable_filename(sel.selected()) {
            Ok(safe) => {
              for ch in safe.safe() {
                let v = ch.to_int()
                if v < 32 {
                  assert_true(false, msg="control character survived sanitisation")
                }
              }
              inspect(safe.safe(), content="a___b")
            }
            Err(e) => assert_true(false, msg="sanitise failed: \{e.to_display()}")
          }
        }
        Err(e) => assert_true(false, msg="resolve failed: \{e.to_display()}")
      }
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "path traversal names never survive the sanitizer as separators" {
  for name in ["../etc/passwd", "..\\..\\boot.ini", "..", ".", "/etc/passwd", "a/../../b"] {
    match sanitize_portable_filename(name) {
      Ok(r) => {
        let safe = r.safe()
        assert_true(!safe.contains("/"), msg="slash survived for \{name}: \{safe}")
        assert_true(!safe.contains("\\"), msg="backslash survived for \{name}: \{safe}")
        assert_true(safe != "." && safe != "..", msg="dot name survived for \{name}: \{safe}")
      }
      Err(e) => assert_true(false, msg="unexpected error for \{name}: \{e.to_display()}")
    }
  }
}

test "a parameter bomb is rejected" {
  // 300 parameters is far beyond the default 256 bound.
  let sb = StringBuilder()
  sb.write_string("attachment")
  for i = 0; i < 300; i = i + 1 {
    sb.write_string("; p\{i}=x")
  }
  match parse_content_disposition(sb.to_string()) {
    Ok(_) => assert_true(false, msg="expected a limit error")
    Err(e) => inspect(e.kind().to_string(), content="LimitExceeded")
  }
}

test "an oversized header is rejected" {
  let options = ParseOptions::strict()
  let big = repeat_str("x", 17000)
  match parse_content_disposition_with_options("attachment; size=\{big}", options) {
    Ok(_) => assert_true(false, msg="expected a limit error")
    Err(e) => inspect(e.kind().to_string(), content="LimitExceeded")
  }
}

test "semicolons inside quoted values are data, not separators" {
  // A naive split(";") would see three parameters; the parser sees one.
  let cd = parse_content_disposition("attachment; filename=\"a;b;c.txt\"").unwrap()
  inspect(cd.parameter_count(), content="1")
  match cd.filename() {
    Some(f) => inspect(f, content="a;b;c.txt")
    None => assert_true(false, msg="filename missing")
  }
}

test "a duplicate filename cannot override a safe one in strict mode" {
  expect_parse_error(
    "attachment; filename=report.pdf; filename=evil.exe",
    "ParameterName",
    "DuplicateParameter",
  )
}

test "an unquoted filename is limited to the token alphabet" {
  // '=' is a separator, so an unquoted value cannot contain it; quoting is
  // the safe carrier for arbitrary data. An unquoted '=' in a value is
  // reported as trailing input.
  expect_parse_error("attachment; filename=a=b", "Input", "TrailingInput")
  expect_parse("attachment; filename=\"a=b\"", "attachment; filename=\"a=b\"")
}

test "the sanitizer never emits an empty or dot-only name for non-empty input" {
  // Except for all-dot inputs, which are rejected outright (see
  // filename_sanitize_test); for every other input the result is usable.
  let cases = ["a", " a", "a ", " .", ". ", "..a", "a..", "-", "_"]
  for name in cases {
    match sanitize_portable_filename(name) {
      Ok(r) => {
        assert_true(r.safe().char_length() > 0, msg="empty safe for \{name}")
        assert_true(r.safe() != "." && r.safe() != "..")
      }
      Err(_) => assert_true(false, msg="unexpected error for \{name}")
    }
  }
}
