// canonicalize_test.mbt — Idempotent canonicalisation (RFC 6266 order rules).

test "canonicalize lower-cases the disposition type" {
  match canonicalize_content_disposition("ATTACHMENT; filename=x") {
    Ok(s) => inspect(s, content="attachment; filename=x")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "canonicalize lower-cases parameter names" {
  match canonicalize_content_disposition("attachment; FILE=PDF") {
    Ok(s) => inspect(s, content="attachment; file=PDF")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "canonicalize keeps parameter order when no filename is present" {
  match canonicalize_content_disposition("attachment; z=1; a=2") {
    Ok(s) => inspect(s, content="attachment; z=1; a=2")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "canonicalize re-encodes extended values with uppercase hex" {
  match canonicalize_content_disposition("attachment; filename*=utf-8'en'caf%C3%A9") {
    Ok(s) => inspect(s, content="attachment; filename*=UTF-8'en'caf%C3%A9")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "canonicalize puts the plain filename before filename*" {
  match canonicalize_content_disposition("attachment; filename*=UTF-8''%E4%B8%AD; filename=fallback.txt") {
    Ok(s) => inspect(s, content="attachment; filename=fallback.txt; filename*=UTF-8''%E4%B8%AD")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "canonicalize keeps a single filename in place" {
  match canonicalize_content_disposition("attachment; filename=report.pdf") {
    Ok(s) => inspect(s, content="attachment; filename=report.pdf")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "canonicalize of a canonical value is a no-op" {
  let inputs = [
    "attachment; filename=report.pdf",
    "inline",
    "attachment; filename=fallback.txt; filename*=UTF-8'en'caf%C3%A9",
    "form-data; name=field; filename=\"a b.txt\"",
  ]
  for input in inputs {
    match canonicalize_content_disposition(input) {
      Ok(c) => inspect(c, content=input)
      Err(e) => assert_true(false, msg="unexpected error for \{input}: \{e.to_display()}")
    }
  }
}

test "canonicalize propagates parse errors" {
  match canonicalize_content_disposition("") {
    Ok(_) => assert_true(false, msg="expected an error")
    Err(e) => inspect(e.kind().to_string(), content="EmptyInput")
  }
  match canonicalize_content_disposition("attachment !") {
    Ok(_) => assert_true(false, msg="expected an error")
    Err(e) => inspect(e.kind().to_string(), content="TrailingInput")
  }
}

test "canonicalize is idempotent (500+ property cases)" {
  let rng = prng(701)
  let failures : Array[String] = []
  let mut cases = 0
  for _i = 0; _i < 600; _i = _i + 1 {
    let input = make_random_cd(rng)
    match canonicalize_content_disposition(input) {
      Ok(c1) => {
        cases = cases + 1
        match canonicalize_content_disposition(c1) {
          Ok(c2) =>
            if c1 != c2 {
              failures.push("non-idempotent for \{input}: \{c1} -> \{c2}")
            }
          Err(e) => failures.push("second canonicalize failed for \{input}: \{e.to_display()}")
        }
      }
      Err(_) => ()
    }
  }
  assert_true(cases >= 500, msg="only \{cases} cases ran; the generator should exceed 500")
  assert_true(failures.length() == 0, msg="failures: \{show_strings(failures)}")
}

test "canonicalize of a parse of a canonicalize is stable across forms" {
  // The same semantic value in two different wire forms canonicalises to the
  // same string.
  let forms = [
    "attachment; filename=\"report.pdf\"",
    "ATTACHMENT; filename=\"report.pdf\"",
    "attachment; FILENAME=\"report.pdf\"",
  ]
  match canonicalize_content_disposition(forms[0]) {
    Ok(c0) =>
      for i = 1; i < forms.length(); i = i + 1 {
        match canonicalize_content_disposition(forms[i]) {
          Ok(c) => inspect(c, content=c0)
          Err(e) => assert_true(false, msg="unexpected error for \{forms[i]}: \{e.to_display()}")
        }
      }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "canonicalize defers filename* past later parameters" {
  // The fallback-before-primary invariant holds even when the plain filename
  // is not the first parameter and filename* is not the last.
  match canonicalize_content_disposition("attachment; size=3; filename*=UTF-8''a; filename=b") {
    Ok(s) => inspect(s, content="attachment; size=3; filename=b; filename*=UTF-8''a")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}
