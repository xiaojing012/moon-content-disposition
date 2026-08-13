// property_test.mbt — Determinism and generator-consistency properties.

test "the PRNG is deterministic for a fixed seed" {
  let a = prng(1234)
  let b = prng(1234)
  let mut same = true
  for _i = 0; _i < 100; _i = _i + 1 {
    if a.next_int() != b.next_int() {
      same = false
    }
  }
  assert_true(same)
}

test "different seeds give different sequences" {
  let a = prng(1234)
  let b = prng(4321)
  let mut differs = false
  for _i = 0; _i < 100; _i = _i + 1 {
    if a.next_int() != b.next_int() {
      differs = true
    }
  }
  assert_true(differs)
}

test "the PRNG stays within [1, 2^31-1]" {
  let rng = prng(7)
  let mut ok = true
  for _i = 0; _i < 1000; _i = _i + 1 {
    let v = rng.next_int()
    if v < 1 || v >= 2147483647 {
      ok = false
    }
  }
  assert_true(ok)
}

test "random tokens are valid HTTP tokens" {
  let rng = prng(55)
  let mut ok = true
  for _i = 0; _i < 500; _i = _i + 1 {
    if !validate_token(random_token(rng, 20)) {
      ok = false
    }
  }
  assert_true(ok)
}

test "the library version is a single semantic version string" {
  let v = library_version()
  assert_true(v != "")
  assert_true(v.contains("."))
  // The single source of truth for the module version lives in moon.mod as
  // the same literal; library_version() is what the CLI reports.
  assert_true(v == "0.1.1")
}

test "the corpus of explicit cases all parse deterministically" {
  let corpus : Array[String] = [
    "inline",
    "attachment",
    "attachment; filename=x",
    "attachment; filename=\"x y\"",
    "form-data; name=field",
    "attachment; filename*=UTF-8''a",
    "attachment; filename*=UTF-8'en'a",
    "attachment; filename=fallback; filename*=UTF-8''%E4%B8%AD",
  ]
  for input in corpus {
    match parse_content_disposition(input) {
      Ok(cd) => {
        match parse_content_disposition(input) {
          Ok(cd2) => assert_true(cd.semantic_equal(cd2), msg="non-deterministic parse of \{input}")
          Err(e) => assert_true(false, msg="second parse failed: \{e.to_display()}")
        }
      }
      Err(e) => assert_true(false, msg="parse failed for \{input}: \{e.to_display()}")
    }
  }
}

test "parameter count matches the number of semicolons plus one" {
  let rng = prng(66)
  let mut ok = true
  for _i = 0; _i < 300; _i = _i + 1 {
    let input = make_random_cd(rng)
    match parse_content_disposition(input) {
      Ok(cd) => {
        let mut semicolons = 0
        for ch in input {
          if ch == ';' {
            semicolons = semicolons + 1
          }
        }
        if cd.parameter_count() != semicolons {
          ok = false
        }
      }
      Err(_) => ()
    }
  }
  assert_true(ok)
}

test "generated values always reparse under strict mode" {
  let rng = prng(77)
  let mut ok = true
  for _i = 0; _i < 300; _i = _i + 1 {
    let name = random_unicode_name(rng, 12)
    match generate_attachment(name) {
      Ok(header) => {
        match parse_content_disposition(header) {
          Ok(_) => ()
          Err(_) => {
            ok = false
          }
        }
      }
      Err(_) => ok = false
    }
  }
  assert_true(ok)
}

test "ASCII filenames round-trip through generate, parse and resolve" {
  // FILE_ALPHABET is deliberately full of characters that are tricky on the
  // wire (`;`, `=`, `#`, `%`, `+`, `&`, `.`, spaces); the quoted-string form
  // must preserve every one of them through generate -> parse -> resolve.
  let rng = prng(88)
  let mut ok = true
  for _i = 0; _i < 300; _i = _i + 1 {
    let name = random_filename(rng, 12)
    match generate_attachment(name) {
      Err(_) => ok = false
      Ok(header) => {
        match parse_content_disposition(header) {
          Err(_) => ok = false
          Ok(cd) => {
            match resolve_filename(cd) {
              Err(_) => ok = false
              Ok(sel) => {
                if sel.selected() != name {
                  ok = false
                }
              }
            }
          }
        }
      }
    }
  }
  assert_true(ok, msg="an ASCII filename did not round-trip through generate/parse/resolve")
}
