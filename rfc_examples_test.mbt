// rfc_examples_test.mbt — The worked examples from RFC 6266 and RFC 8187.

test "RFC 6266 section 5 examples parse" {
  expect_parse("attachment", "attachment")
  expect_parse("attachment; filename=\"example.html\"", "attachment; filename=\"example.html\"")
  expect_parse("inline; filename=\"foo.html\"", "inline; filename=\"foo.html\"")
  expect_parse(
    "form-data; name=\"field\"; filename=\"example.txt\"",
    "form-data; name=\"field\"; filename=\"example.txt\"",
  )
  expect_parse(
    "attachment; filename=\"EURO rates\"; filename*=utf-8''%e2%82%ac%20rates",
    "attachment; filename=\"EURO rates\"; filename*=UTF-8''€ rates",
  )
}

test "RFC 8187 euro example decodes to the euro sign" {
  match parse_content_disposition("attachment; filename*=UTF-8''%e2%82%ac%20rates") {
    Ok(cd) => {
      match cd.filename_star() {
        Some(ev) => {
          inspect(ev.value(), content="€ rates")
          inspect(ev.charset(), content="UTF-8")
        }
        None => assert_true(false, msg="filename* missing")
      }
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "RFC 8187 example resolves with filename* precedence" {
  let cd = parse_content_disposition(
    "attachment; filename=\"EURO rates\"; filename*=utf-8''%e2%82%ac%20rates",
  ).unwrap()
  match resolve_filename(cd) {
    Ok(sel) => {
      inspect(sel.selected(), content="€ rates")
      inspect(filename_source_name(sel.source()), content="filename*")
      assert_true(sel.fallback())
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "RFC 8187 UTF-8 is the only required charset and works" {
  match parse_content_disposition("attachment; filename*=UTF-8''foo%20bar.pdf") {
    Ok(cd) => {
      match cd.filename_star() {
        Some(ev) => inspect(ev.value(), content="foo bar.pdf")
        None => assert_true(false, msg="filename* missing")
      }
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "RFC 6266 fallback rule prefers filename* for the resolved name" {
  let cd = parse_content_disposition("attachment; filename=fallback.txt; filename*=UTF-8''primary.pdf").unwrap()
  match resolve_filename(cd) {
    Ok(sel) => inspect(sel.selected(), content="primary.pdf")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "RFC 6266 form-data example keeps extension parameters" {
  let cd = parse_content_disposition("form-data; name=\"field\"; filename=\"example.txt\"").unwrap()
  inspect(cd.parameter_count(), content="2")
  match cd.get_parameter("name") {
    Some(p) => {
      match p.value().plain() {
        Some(v) => inspect(v, content="field")
        None => assert_true(false, msg="expected a plain value")
      }
    }
    None => assert_true(false, msg="name parameter missing")
  }
}

test "a bare disposition type with no filename parses" {
  let cd = parse_content_disposition("attachment").unwrap()
  inspect(cd.parameter_count(), content="0")
  assert_true(cd.filename() is None)
}

test "the RFC 6266 examples serialise back to canonical form" {
  let inputs = [
    ("attachment", "attachment"),
    ("attachment; filename=\"example.html\"", "attachment; filename=\"example.html\""),
    ("inline; filename=\"foo.html\"", "inline; filename=\"foo.html\""),
    ("form-data; name=\"field\"; filename=\"example.txt\"", "form-data; name=\"field\"; filename=\"example.txt\""),
  ]
  for pair in inputs {
    let (input, expected) = pair
    match parse_content_disposition(input) {
      Ok(cd) => {
        match serialize_content_disposition(cd) {
          Ok(s) => inspect(s, content=expected)
          Err(e) => assert_true(false, msg="serialise failed: \{e.to_display()}")
        }
      }
      Err(e) => assert_true(false, msg="parse failed for \{input}: \{e.to_display()}")
    }
  }
}
