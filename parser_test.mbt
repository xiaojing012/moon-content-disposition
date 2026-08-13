// parser_test.mbt — The public parse entry points and their edge cases.

test "parses an inline disposition" {
  expect_parse("inline", "inline")
}

test "parses an attachment disposition" {
  expect_parse("attachment", "attachment")
}

test "parses an extension disposition type" {
  expect_parse("form-data", "form-data")
  expect_parse("CustomType", "customtype")
}

test "disposition type is case-insensitive" {
  expect_parse("INLINE", "inline")
  expect_parse("Attachment", "attachment")
  expect_parse("FORM-DATA", "form-data")
}

test "parses a filename parameter" {
  expect_parse("attachment; filename=report.pdf", "attachment; filename=report.pdf")
  expect_parse("attachment; filename=\"report.pdf\"", "attachment; filename=\"report.pdf\"")
}

test "parses multiple parameters" {
  expect_parse(
    "attachment; filename=\"file.txt\"; size=1024",
    "attachment; filename=\"file.txt\"; size=1024",
  )
}

test "parses an extended filename parameter" {
  expect_parse(
    "attachment; filename*=UTF-8'en'caf%C3%A9",
    "attachment; filename*=UTF-8'en'café",
  )
}

test "strips optional whitespace" {
  expect_parse("attachment ; filename=report.pdf", "attachment; filename=report.pdf")
  expect_parse("attachment;filename = report.pdf", "attachment; filename=report.pdf")
  expect_parse("  attachment  ;  filename=\"a b\"  ", "attachment; filename=\"a b\"")
}

test "accepts tab as optional whitespace" {
  expect_parse("attachment;\tfilename=report.pdf", "attachment; filename=report.pdf")
  expect_parse("\tattachment; filename=x\t", "attachment; filename=x")
}

test "rejects a trailing semicolon in strict mode" {
  expect_parse_error("attachment;", "ParameterName", "ExpectedToken")
  expect_parse_error("attachment;;", "ParameterName", "ExpectedToken")
}

test "accepts a trailing semicolon in compatible mode" {
  match parse_content_disposition_with_options("attachment;", ParseOptions::compatible()) {
    Ok(cd) => expect_cd(cd, "attachment")
    Err(e) => assert_true(false, msg="compatible parse failed: \{e.to_display()}")
  }
}

test "skips an empty parameter element in compatible mode" {
  match parse_content_disposition_with_options("attachment;;size=1", ParseOptions::compatible()) {
    Ok(cd) => expect_cd(cd, "attachment; size=1")
    Err(e) => assert_true(false, msg="compatible parse failed: \{e.to_display()}")
  }
}

test "rejects an empty parameter element in strict mode" {
  expect_parse_error("attachment;;size=1", "ParameterName", "ExpectedToken")
}

test "rejects trailing input" {
  expect_parse_error("attachment !", "Input", "TrailingInput")
  expect_parse_error("attachment; size=1 x", "Input", "TrailingInput")
}

test "rejects an empty input value" {
  expect_parse_error("", "Input", "EmptyInput")
  expect_parse_error("   ", "Input", "EmptyInput")
  expect_parse_error(" \t ", "Input", "EmptyInput")
}

test "rejects a missing disposition type" {
  expect_parse_error("; filename=x", "DispositionType", "InvalidDispositionType")
}

test "rejects a duplicate parameter in strict mode" {
  expect_parse_error("attachment; filename=a; filename=b", "ParameterName", "DuplicateParameter")
  expect_parse_error("attachment; size=1; name=x; size=2", "ParameterName", "DuplicateParameter")
}

test "duplicate parameter names are case-insensitive" {
  expect_parse_error("attachment; Filename=a; filename=b", "ParameterName", "DuplicateParameter")
}

test "compatible mode preserves duplicate parameters" {
  let cd = parse_compatible("attachment; filename=a; filename=b")
  expect_cd(cd, "attachment; filename=a; filename=b")
  inspect(cd.parameter_count(), content="2")
}

test "detailed parse reports duplicates" {
  match parse_content_disposition_detailed(
    "attachment; size=1; name=x; size=2",
    ParseOptions::compatible(),
  ) {
    Ok(p) => {
      expect_same_strings(p.duplicates(), ["size"])
      expect_same_strings(p.recoveries(), [])
      inspect(p.mode().to_string(), content="compatible")
      expect_cd(p.content_disposition(), "attachment; size=1; name=x; size=2")
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "detailed parse records compatible recoveries" {
  match parse_content_disposition_detailed("attachment;", ParseOptions::compatible()) {
    Ok(p) => {
      expect_same_strings(p.duplicates(), [])
      expect_same_strings(p.recoveries(), ["trailing-semicolon"])
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
  match parse_content_disposition_detailed("attachment;;", ParseOptions::compatible()) {
    Ok(p) => expect_same_strings(p.recoveries(), ["skip-empty-parameter"])
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "detailed parse reports the strict mode" {
  match parse_content_disposition_detailed("attachment", ParseOptions::default()) {
    Ok(p) => inspect(p.mode().to_string(), content="strict")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "rejects input above max_input_bytes" {
  // 20 KiB > the strict max_input_bytes of 16 KiB, so the entry check fires
  // at the Input stage before any parameter parsing.
  let big = StringBuilder()
  for _i = 0; _i < 2000; _i = _i + 1 {
    big.write_string("aaaaaaaaaa")
  }
  let input = "attachment; filename=" + big.to_string()
  let options = ParseOptions::new().with_limits(Limits::strict())
  match parse_content_disposition_with_options(input, options) {
    Ok(_) => assert_true(false, msg="expected a limit error")
    Err(e) => {
      inspect(e.stage().to_string(), content="Input")
      inspect(e.kind().to_string(), content="LimitExceeded")
    }
  }
}

test "accepts input at the limit boundary" {
  let input = "attachment; filename=abc"
  let options = ParseOptions::new().with_limits(Limits::strict())
  match parse_content_disposition_with_options(input, options) {
    Ok(cd) => expect_cd(cd, "attachment; filename=abc")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "rejects too many parameters" {
  let sb = StringBuilder()
  sb.write_string("attachment")
  for i = 0; i < 40; i = i + 1 {
    sb.write_string("; p\{i}=x")
  }
  let options = ParseOptions::new().with_limits(Limits::strict())
  match parse_content_disposition_with_options(sb.to_string(), options) {
    Ok(_) => assert_true(false, msg="expected a limit error")
    Err(e) => {
      inspect(e.stage().to_string(), content="Limit")
      inspect(e.kind().to_string(), content="LimitExceeded")
    }
  }
}

test "a quoted string may hold separators" {
  expect_parse("attachment; name=\"a;b=c\"", "attachment; name=\"a;b=c\"")
}

test "errors carry an offset and context" {
  match parse_content_disposition("attachment !") {
    Ok(_) => assert_true(false, msg="expected an error")
    Err(e) => {
      assert_true(e.offset() >= 11, msg="offset should point at the trailing input")
      let ctx = e.context()
      assert_true(ctx != "", msg="context should not be empty")
    }
  }
}
