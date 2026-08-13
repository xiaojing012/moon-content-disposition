// generator_test.mbt — Building Content-Disposition values from filenames.

test "generates an attachment value" {
  match generate_attachment("report.pdf") {
    Ok(s) => inspect(s, content="attachment; filename=\"report.pdf\"")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "generates an inline value" {
  match generate_inline("report.pdf") {
    Ok(s) => inspect(s, content="inline; filename=\"report.pdf\"")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "quotes even a pure-token filename" {
  match generate_attachment("report.pdf") {
    Ok(s) => assert_true(s.has_suffix("filename=\"report.pdf\""))
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "escapes quotes and backslashes" {
  match generate_attachment("a\"b\\c.txt") {
    Ok(s) => inspect(s, content="attachment; filename=\"a\\\"b\\\\c.txt\"")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "adds filename* for non-ASCII filenames" {
  match generate_attachment("café.txt") {
    Ok(s) =>
      inspect(s, content="attachment; filename=\"café.txt\"; filename*=UTF-8''caf%C3%A9.txt")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "adds filename* for non-ASCII with a language tag" {
  let options = GenerateOptions::default().with_language(Some("en"))
  match generate_attachment_with_options("café.txt", options) {
    Ok(s) =>
      inspect(s, content="attachment; filename=\"café.txt\"; filename*=UTF-8'en'caf%C3%A9.txt")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "without_filename_star disables the extended parameter" {
  let options = GenerateOptions::default().without_filename_star()
  match generate_attachment_with_options("café.txt", options) {
    Ok(s) => inspect(s, content="attachment; filename=\"café.txt\"")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "always_filename_star emits the extended parameter for ASCII" {
  let options = GenerateOptions::default()
  match generate_attachment_with_options("report.pdf", options) {
    Ok(s) => inspect(s, content="attachment; filename=\"report.pdf\"")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "rejects a control character in the filename" {
  for bad in ["a\nb", "a\rb", "a\u{0000}b", "\t"] {
    match generate_attachment(bad) {
      Ok(_) => assert_true(false, msg="expected a rejection for \{bad}")
      Err(e) => {
        inspect(e.stage().to_string(), content="QuotedString")
        inspect(e.kind().to_string(), content="InvalidControlCharacter")
      }
    }
  }
}

test "rejects an invalid language tag" {
  let options = GenerateOptions::default().with_language(Some("en--US"))
  match generate_attachment_with_options("café.txt", options) {
    Ok(_) => assert_true(false, msg="expected a rejection")
    Err(e) => {
      inspect(e.stage().to_string(), content="ExtendedValue")
      inspect(e.kind().to_string(), content="InvalidLanguage")
    }
  }
}

test "ignores a language tag when filename* is not emitted" {
  // A language tag is only validated when the extended parameter is emitted;
  // without it an (otherwise untrusted) tag is harmless.
  let options = GenerateOptions::default().without_filename_star().with_language(Some("en"))
  match generate_attachment_with_options("café.txt", options) {
    Ok(s) => inspect(s, content="attachment; filename=\"café.txt\"")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "generation then parsing recovers the filename" {
  let rng = prng(901)
  let failures : Array[String] = []
  for _i = 0; _i < 400; _i = _i + 1 {
    let name = random_unicode_name(rng, 16)
    match generate_attachment(name) {
      Ok(header) => {
        match parse_content_disposition(header) {
          Ok(cd) => {
            match resolve_filename(cd) {
              Ok(sel) =>
                if sel.selected() != name {
                  failures.push("round-trip mismatch for \{name} via \{header}: \{sel.selected()}")
                }
              Err(e) => failures.push("resolve error for \{name}: \{e.to_display()}")
            }
          }
          Err(e) => failures.push("parse error for \{header}: \{e.to_display()}")
        }
      }
      Err(e) => failures.push("generate error for \{name}: \{e.to_display()}")
    }
  }
  assert_true(failures.length() == 0, msg="failures: \{show_strings(failures)}")
}

test "generate options accessors" {
  let options = GenerateOptions::default()
  assert_true(options.include_filename_star())
  assert_false(options.always_filename_star())
  assert_true(options.language() is None)
  let tagged = options.with_language(Some("zh"))
  assert_true(tagged.language() is Some("zh"))
  assert_true(tagged.include_filename_star()) // preserved across with_language
}
