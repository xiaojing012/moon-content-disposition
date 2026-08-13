// resolver_test.mbt — RFC 6266 Section 4.3 filename precedence resolution.

test "resolves the plain filename" {
  let cd = parse_content_disposition("attachment; filename=report.pdf").unwrap()
  match resolve_filename(cd) {
    Ok(s) => {
      inspect(s.selected(), content="report.pdf")
      inspect(filename_source_name(s.source()), content="filename")
      assert_false(s.fallback())
      expect_same_strings(s.warnings(), [])
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "resolves filename* with precedence over filename" {
  let cd = parse_content_disposition("attachment; filename=fallback.txt; filename*=UTF-8'en'caf%C3%A9.txt").unwrap()
  match resolve_filename(cd) {
    Ok(s) => {
      inspect(s.selected(), content="café.txt")
      inspect(filename_source_name(s.source()), content="filename*")
      assert_true(s.fallback())
      expect_same_strings(s.warnings(), ["filename-star-precedence"])
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "resolves filename* without a plain fallback" {
  let cd = parse_content_disposition("attachment; filename*=UTF-8''%E4%B8%AD%E6%96%87").unwrap()
  match resolve_filename(cd) {
    Ok(s) => {
      inspect(s.selected(), content="中文")
      inspect(filename_source_name(s.source()), content="filename*")
      assert_false(s.fallback())
      expect_same_strings(s.warnings(), [])
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "warns about path separators" {
  let cd = parse_content_disposition("attachment; filename=\"../evil.exe\"").unwrap()
  match resolve_filename(cd) {
    Ok(s) => {
      inspect(s.selected(), content="../evil.exe")
      expect_same_strings(s.warnings(), ["contains-path-separator"])
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "warns about backslash path separators" {
  // A literal backslash must be escaped as '\\' in the quoted string; an
  // unescaped backslash would escape the next character instead.
  let cd = parse_content_disposition("attachment; filename=\"a\\\\b\"").unwrap()
  match resolve_filename(cd) {
    Ok(s) => expect_same_strings(s.warnings(), ["contains-path-separator"])
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "warns about control characters" {
  // A raw NUL cannot be quoted in strict mode, so the control character is
  // carried through an RFC 8187 percent-encoded extended value instead.
  let cd = parse_content_disposition("attachment; filename*=UTF-8''a%00b").unwrap()
  match resolve_filename(cd) {
    Ok(s) => expect_same_strings(s.warnings(), ["contains-control-character"])
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "warns about an empty filename" {
  let cd = parse_content_disposition("attachment; filename=\"\"").unwrap()
  match resolve_filename(cd) {
    Ok(s) => {
      inspect(s.selected(), content="")
      expect_same_strings(s.warnings(), ["empty-filename"])
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "errors when no filename is present" {
  let cd = parse_content_disposition("attachment").unwrap()
  match resolve_filename(cd) {
    Ok(_) => assert_true(false, msg="expected an error")
    Err(e) => {
      inspect(e.stage().to_string(), content="FilenameResolution")
      inspect(e.kind().to_string(), content="InvalidFilename")
    }
  }
}

test "errors when only extension parameters are present" {
  let cd = parse_content_disposition("attachment; size=1024").unwrap()
  match resolve_filename(cd) {
    Ok(_) => assert_true(false, msg="expected an error")
    Err(e) => inspect(e.kind().to_string(), content="InvalidFilename")
  }
}

test "warns once for repeated separators" {
  let cd = parse_content_disposition("attachment; filename=\"a/b/c\"").unwrap()
  match resolve_filename(cd) {
    Ok(s) => expect_same_strings(s.warnings(), ["contains-path-separator"])
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "combined warnings are deduplicated" {
  // '/' and a control character carried through an RFC 8187 value (a raw
  // control byte cannot be quoted in strict mode).
  let cd = parse_content_disposition("attachment; filename*=UTF-8''a%2Fb%01c").unwrap()
  match resolve_filename(cd) {
    Ok(s) => {
      expect_same_strings(s.warnings(), ["contains-path-separator", "contains-control-character"])
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "filename* value is decoded before selection" {
  let cd = parse_content_disposition("attachment; filename*=ISO-8859-1''caf%E9").unwrap()
  match resolve_filename(cd) {
    Ok(s) => inspect(s.selected(), content="café")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

// FilenameSource carries a stable programmatic name; the enum value itself
// cannot be constructed from the blackbox test package, so the source is
// compared through this helper.
fn filename_source_name(src : FilenameSource) -> String {
  match src {
    Filename => "filename"
    FilenameStar => "filename*"
  }
}
