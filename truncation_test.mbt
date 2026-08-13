// truncation_test.mbt — Safety under very large inputs: error contexts are
// bounded, nothing is echoed in full, and nothing overflows.

test "an error context never echoes the whole input" {
  // A 2 KiB header with an unterminated quoted string at the very end: the
  // context string must be a small window, not the whole value.
  let big = StringBuilder()
  big.write_string("attachment; filename=\"")
  for _i = 0; _i < 200; _i = _i + 1 {
    big.write_string("aaaaaaaaaa")
  }
  // deliberately no closing quote
  let input = big.to_string()
  match parse_content_disposition(input) {
    Ok(_) => assert_true(false, msg="expected an error")
    Err(e) => {
      assert_true(e.context().char_length() <= 80, msg="context too long: \{e.context()}")
      assert_true(e.context().char_length() >= 1)
      assert_true(input.length() > 1000, msg="the input really should be large")
    }
  }
}

test "a short error context is the input itself" {
  match parse_content_disposition("attachment !") {
    Ok(_) => assert_true(false, msg="expected an error")
    Err(e) => inspect(e.context(), content="attachment !") // short input: the whole value is the window
  }
}

test "scanner context strings are bounded at every position" {
  let big = repeat_str("b", 1000)
  let s = Scanner::new(big)
  s.seek(500)
  let ctx = s.context_string()
  assert_true(ctx.char_length() <= 80, msg="context too long: \{ctx}")
  let s2 = Scanner::new(big)
  s2.seek(999)
  assert_true(s2.context_string().char_length() <= 80)
}

test "scanner context strings include an ellipsis for long inputs" {
  let big = repeat_str("c", 1000)
  let s = Scanner::new(big)
  s.seek(500)
  let ctx = s.context_string()
  assert_true(ctx.has_prefix("..."))
  assert_true(ctx.has_suffix("..."))
}

test "a quoted value at the length limit parses without truncation" {
  // Values are bounded by an explicit limit and rejected, never silently
  // truncated: a 900-byte value (under the default 8192 limit) round-trips.
  let value = repeat_str("q", 900)
  let header = "attachment; filename=\"\{value}\""
  match parse_content_disposition(header) {
    Ok(cd) => {
      match cd.filename() {
        Some(f) => {
          assert_true(f.char_length() == 900)
          inspect(f.char_length(), content="900")
        }
        None => assert_true(false, msg="filename missing")
      }
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "a value just over the strict limit is rejected, not truncated" {
  let value = repeat_str("q", 1025)
  let options = ParseOptions::strict()
  match parse_content_disposition_with_options("attachment; size=\{value}", options) {
    Ok(_) => assert_true(false, msg="expected a limit error")
    Err(e) => inspect(e.kind().to_string(), content="LimitExceeded")
  }
}

test "error display is a single bounded line" {
  match parse_content_disposition("attachment; filename=\"unterminated") {
    Ok(_) => assert_true(false, msg="expected an error")
    Err(e) => {
      let line = e.to_display()
      assert_true(line.char_length() < 200)
      assert_true(line.contains("UnterminatedQuotedString"))
    }
  }
}
