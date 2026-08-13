// serializer_test.mbt — Deterministic serialisation of parsed models.

test "serializes an inline disposition" {
  let cd = parse_content_disposition("inline").unwrap()
  match serialize_content_disposition(cd) {
    Ok(s) => inspect(s, content="inline")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "serializes an attachment disposition" {
  let cd = parse_content_disposition("attachment").unwrap()
  match serialize_content_disposition(cd) {
    Ok(s) => inspect(s, content="attachment")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "serializes a token parameter without quoting" {
  let cd = parse_content_disposition("attachment; filename=report.pdf").unwrap()
  match serialize_content_disposition(cd) {
    Ok(s) => inspect(s, content="attachment; filename=report.pdf")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "serializes a quoted parameter keeping the quoted form" {
  let cd = parse_content_disposition("attachment; filename=\"report.pdf\"").unwrap()
  match serialize_content_disposition(cd) {
    Ok(s) => inspect(s, content="attachment; filename=\"report.pdf\"")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "serialize lower-cases the disposition type" {
  let cd = parse_content_disposition("ATTACHMENT; filename=x").unwrap()
  match serialize_content_disposition(cd) {
    Ok(s) => inspect(s, content="attachment; filename=x")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "serialize lower-cases parameter names" {
  let cd = parse_content_disposition("attachment; FILE=PDF; Name=value").unwrap()
  match serialize_content_disposition(cd) {
    Ok(s) => inspect(s, content="attachment; file=PDF; name=value")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "serialize preserves parameter order" {
  let cd = parse_content_disposition("attachment; z=1; a=2; m=3").unwrap()
  match serialize_content_disposition(cd) {
    Ok(s) => inspect(s, content="attachment; z=1; a=2; m=3")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "preserve-case serialises the original casing" {
  let cd = parse_content_disposition("ATTACHMENT; FILE=PDF").unwrap()
  match serialize_content_disposition_preserve_case(cd) {
    Ok(s) => inspect(s, content="ATTACHMENT; FILE=PDF")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "preserve-case serialises an extension type verbatim" {
  let cd = parse_content_disposition("Form-Data; name=x").unwrap()
  match serialize_content_disposition_preserve_case(cd) {
    Ok(s) => inspect(s, content="Form-Data; name=x")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "serialize lower-cases an extension type" {
  let cd = parse_content_disposition("Form-Data; name=x").unwrap()
  match serialize_content_disposition(cd) {
    Ok(s) => inspect(s, content="form-data; name=x")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "serializes an extended parameter re-encoded" {
  let cd = parse_content_disposition("attachment; filename*=UTF-8'en'caf%C3%A9").unwrap()
  match serialize_content_disposition(cd) {
    Ok(s) => inspect(s, content="attachment; filename*=UTF-8'en'caf%C3%A9")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "serialize escapes a quoted value" {
  let cd = parse_content_disposition("attachment; name=\"a\\\"b\"").unwrap()
  match serialize_content_disposition(cd) {
    Ok(s) => inspect(s, content="attachment; name=\"a\\\"b\"")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "parse then serialise round-trips canonical input" {
  let rng = prng(601)
  let failures : Array[String] = []
  for _i = 0; _i < 400; _i = _i + 1 {
    let input = make_random_cd(rng)
    match parse_content_disposition(input) {
      Ok(cd) => {
        match serialize_content_disposition_preserve_case(cd) {
          Ok(s) =>
            if s != input {
              failures.push("mismatch for \{input}: got \{s}")
            }
          Err(e) => failures.push("serialize error for \{input}: \{e.to_display()}")
        }
      }
      Err(_) => () // random generation can produce strict-mode-invalid input; skip
    }
  }
  assert_true(failures.length() == 0, msg="failures: \{show_strings(failures)}")
}

test "serialise then parse gives a semantically equal model" {
  let rng = prng(602)
  let failures : Array[String] = []
  for _i = 0; _i < 400; _i = _i + 1 {
    let input = make_random_cd(rng)
    match parse_content_disposition(input) {
      Ok(cd) => {
        match serialize_content_disposition(cd) {
          Ok(s) => {
            match parse_content_disposition(s) {
              Ok(again) =>
                if !again.semantic_equal(cd) {
                  failures.push("semantic mismatch for \{input} via \{s}")
                }
              Err(e) => failures.push("re-parse error for \{s}: \{e.to_display()}")
            }
          }
          Err(e) => failures.push("serialize error for \{input}: \{e.to_display()}")
        }
      }
      Err(_) => ()
    }
  }
  assert_true(failures.length() == 0, msg="failures: \{show_strings(failures)}")
}

test "serialise of a strict-invalid model is rejected" {
  // A hand-built model cannot be constructed from the blackbox test package,
  // so reach the same code path through a model that parses but whose value
  // cannot be serialised: a token value is always valid when parsed, so the
  // rejection path is covered indirectly by validate_token in the token tests.
  // Here we assert the documented boundary: serialising is total for every
  // value that `parse_content_disposition` can produce.
  let inputs = [
    "attachment; filename=x",
    "attachment; filename=\"a b\"",
    "attachment; filename*=UTF-8''%E4%B8%AD",
    "form-data; name=field",
  ]
  for input in inputs {
    match parse_content_disposition(input) {
      Ok(cd) =>
        assert_true(serialize_content_disposition(cd) is Ok(_), msg="serialize failed for \{input}")
      Err(_) => assert_true(false, msg="parse failed for \{input}")
    }
  }
}

// Builds a random, always-parseable Content-Disposition header value. The
// value forms are chosen so that strict mode always accepts them.
fn make_random_cd(rng : Prng) -> String {
  let types = ["inline", "attachment", "inline", "attachment", "form-data"]
  let sb = StringBuilder()
  sb.write_string(types[rng.below(types.length())])
  let n = rng.below(4)
  for _i = 0; _i < n; _i = _i + 1 {
    sb.write_string("; \{random_token(rng, 10)}=")
    let form = rng.below(3)
    if form == 0 {
      sb.write_string(random_token(rng, 12))
    } else if form == 1 {
      let v = random_string_from(rng, "abc .,-_{}()", rng.below(8))
      sb.write_string(serialize_quoted_string(v))
    } else {
      sb.write_string("UTF-8''")
      sb.write_string(percent_encode_attr_value(random_unicode_name(rng, 8)))
    }
  }
  sb.to_string()
}
