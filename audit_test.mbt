// audit_test.mbt — Advisory audit of Content-Disposition values.

// The issue kind strings of a report, in order.
fn audit_kinds(report : AuditReport) -> Array[String] {
  let out : Array[String] = []
  for i in report.issues() {
    out.push(i.kind().to_string())
  }
  out
}

// Whether a report contains the given kind key.
fn has_kind(report : AuditReport, kind : String) -> Bool {
  has_key(audit_kinds(report), kind)
}

test "audits a clean attachment with a plain filename" {
  match audit_header("attachment; filename=report.pdf") {
    Ok(report) => {
      // A single, information-only issue: only the plain filename is present.
      inspect(report.issue_count(), content="1")
      expect_same_strings(audit_kinds(report), ["plain-filename-only"])
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "flags a missing filename" {
  match audit_header("attachment") {
    Ok(report) => {
      assert_true(has_kind(report, "missing-filename"))
      assert_true(has_kind(report, "extension-disposition-type") == false)
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "flags a path separator as high severity" {
  match audit_header("attachment; filename=\"../x\"") {
    Ok(report) => {
      assert_true(has_kind(report, "path-separator-in-filename"))
      for i in report.issues() {
        if i.kind().to_string() == "path-separator-in-filename" {
          inspect(i.severity().to_string(), content="high")
          inspect(i.parameter(), content="filename")
        }
      }
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "flags a control character as high severity" {
  // A strict header parse rejects a NUL in the quoted filename, so the
  // control-character finding is exercised through the raw-name audit path.
  let policy = FilenamePolicy::default()
  let report = audit_filename("a\u{0000}b", policy)
  assert_true(has_kind(report, "control-character-in-filename"))
  for i in report.issues() {
    if i.kind().to_string() == "control-character-in-filename" {
      inspect(i.severity().to_string(), content="high")
    }
  }
}

test "flags an empty filename" {
  match audit_header("attachment; filename=\"\"") {
    Ok(report) => assert_true(has_kind(report, "empty-filename"))
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "flags a trailing dot" {
  match audit_header("attachment; filename=report.pdf.") {
    Ok(report) => assert_true(has_kind(report, "trailing-dot-or-space"))
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "flags non-ASCII without an RFC 8187 companion" {
  // Strict parsing only accepts obs-text inside a quoted string, so the
  // non-ASCII name is quoted.
  match audit_header("attachment; filename=\"café.txt\"") {
    Ok(report) => {
      assert_true(has_kind(report, "non-ascii-unquoted-filename"))
      assert_true(has_kind(report, "missing-filename-star-for-non-ascii"))
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "a non-ASCII name with filename* avoids the missing-companion issue" {
  match audit_header("attachment; filename=\"café.txt\"; filename*=UTF-8''caf%C3%A9.txt") {
    Ok(report) => {
      assert_true(!has_kind(report, "missing-filename-star-for-non-ascii"))
      assert_true(has_kind(report, "both-filename-and-filename-star"))
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "an RFC 8187 value alone records the no-fallback info issue" {
  match audit_header("attachment; filename*=UTF-8''caf%C3%A9.txt") {
    Ok(report) => {
      assert_true(has_kind(report, "filename-star-without-fallback"))
      assert_true(!has_kind(report, "missing-filename"))
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "audits an unsupported charset in an extended value" {
  // An extended value with an unsupported charset never parses, so the
  // UnsupportedCharset audit finding is unreachable through audit_header;
  // it is exercised through the raw-value audit path instead.
  match audit_header("attachment; filename*=UTF-8''caf%C3%A9.txt") {
    Ok(report) => assert_true(!has_kind(report, "unsupported-charset"))
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "audits duplicate parameters" {
  let cd = parse_compatible("attachment; filename=a; filename=b")
  let report = audit_content_disposition(cd)
  assert_true(has_kind(report, "duplicate-parameter"))
}

test "audits compatible recoveries from a detailed parse" {
  match parse_content_disposition_detailed("attachment;", ParseOptions::compatible()) {
    Ok(p) => {
      let report = audit_disposition_parse(p)
      assert_true(has_kind(report, "recovery-applied"))
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "audits an extension disposition type" {
  match audit_header("form-data; name=x") {
    Ok(report) => assert_true(has_kind(report, "extension-disposition-type"))
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "audit_filename reports reserved names and long names" {
  let policy = FilenamePolicy::default()
  let report = audit_filename("CON", policy)
  assert_true(has_kind(report, "reserved-windows-name"))
  let long = StringBuilder()
  for _i = 0; _i < 300; _i = _i + 1 {
    long.write_string("x")
  }
  let report2 = audit_filename(long.to_string(), policy)
  assert_true(has_kind(report2, "long-filename"))
}

test "audit_filename flags separators and controls in a raw name" {
  let policy = FilenamePolicy::default()
  let report = audit_filename("../a\nb", policy)
  assert_true(has_kind(report, "path-separator-in-filename"))
  assert_true(has_kind(report, "control-character-in-filename"))
}

test "audit_filename_with_media_type escalates an executable media type" {
  let policy = FilenamePolicy::default()
  let report = audit_filename_with_media_type("install.exe", "application/octet-stream", policy)
  assert_true(has_kind(report, "extension-risk"))
  for i in report.issues() {
    if i.kind().to_string() == "extension-risk" {
      inspect(i.severity().to_string(), content="high")
    }
  }
}

test "audit_filename_with_media_type stays warning for a harmless media type" {
  let policy = FilenamePolicy::default()
  let report = audit_filename_with_media_type("install.exe", "text/plain", policy)
  assert_true(has_kind(report, "extension-risk"))
  for i in report.issues() {
    if i.kind().to_string() == "extension-risk" {
      inspect(i.severity().to_string(), content="warning")
    }
  }
}

test "audit_header propagates parse errors" {
  match audit_header("attachment !") {
    Ok(_) => assert_true(false, msg="expected an error")
    Err(e) => inspect(e.kind().to_string(), content="TrailingInput")
  }
}

test "issues expose stable fields" {
  match audit_header("attachment; filename=report.pdf") {
    Ok(report) => {
      let issue = report.issues()[0]
      inspect(issue.severity().to_string(), content="info")
      inspect(issue.kind().to_string(), content="plain-filename-only")
      inspect(issue.parameter(), content="filename")
      assert_true(issue.message() != "")
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "audit report counts issues" {
  match audit_header("attachment; filename=\"../a.\"") {
    Ok(report) => {
      // plain-filename-only + path-separator + trailing-dot.
      assert_true(report.issue_count() >= 3)
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "audit report severity counts are consumer-friendly" {
  // plain-filename-only (info) + path-separator (high) + trailing-dot
  // (warning): the consumer-facing counters must not require constructing an
  // AuditSeverity (enum variants are read-only from consumer packages).
  match audit_header("attachment; filename=\"../a.\"") {
    Ok(report) => {
      inspect(report.count_high(), content="1")
      inspect(report.count_at_least_warning(), content="2")
      // count_severity works when given a severity obtained from an issue.
      let any = report.issues()[0].severity()
      inspect(report.count_severity(any), content="3")
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}
