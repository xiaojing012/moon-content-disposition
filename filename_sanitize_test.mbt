// filename_sanitize_test.mbt — Policy-driven filename sanitisation,
// including a 1000+ case invariant sweep.

test "portable keeps a clean name unchanged" {
  match sanitize_portable_filename("report.pdf") {
    Ok(r) => {
      inspect(r.safe(), content="report.pdf")
      assert_false(r.changed())
      expect_same_strings(r.issues(), [])
      inspect(r.original(), content="report.pdf")
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "portable replaces a space with an underscore" {
  match sanitize_portable_filename("my report.pdf") {
    Ok(r) => {
      inspect(r.safe(), content="my_report.pdf")
      assert_true(r.changed())
      expect_same_strings(r.issues(), ["replaced-unsafe-character"])
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "portable replaces non-ASCII characters" {
  match sanitize_portable_filename("café.txt") {
    Ok(r) => {
      inspect(r.safe(), content="caf_.txt")
      assert_true(has_key(r.issues(), "replaced-unsafe-character"))
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "portable replaces path separators and records them" {
  match sanitize_portable_filename("../../etc/passwd") {
    Ok(r) => {
      // Every separator becomes an underscore; the slash issue is recorded
      // once (not per occurrence).
      inspect(r.safe(), content=".._.._etc_passwd")
      assert_true(has_key(r.issues(), "replaced-path-separator"))
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "portable replaces a backslash separator" {
  match sanitize_portable_filename("a\\b.txt") {
    Ok(r) => {
      inspect(r.safe(), content="a_b.txt")
      assert_true(has_key(r.issues(), "replaced-path-separator"))
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "portable defuses the whole-name forms dot and dot-dot" {
  match sanitize_portable_filename(".") {
    Ok(r) => {
      inspect(r.safe(), content="_")
      assert_true(has_key(r.issues(), "defused-dot-name"))
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
  match sanitize_portable_filename("..") {
    Ok(r) => {
      inspect(r.safe(), content="_")
      assert_true(has_key(r.issues(), "defused-dot-name"))
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "portable defuses windows reserved names" {
  for name in ["CON", "con", "CON.txt", "PRN", "AUX", "NUL", "COM1", "LPT9"] {
    match sanitize_portable_filename(name) {
      Ok(r) => {
        assert_true(r.safe().has_prefix("_"), msg="\{name} should be prefixed, got \{r.safe()}")
        assert_true(has_key(r.issues(), "prefixed-reserved-name"))
      }
      Err(e) => assert_true(false, msg="unexpected error for \{name}: \{e.to_display()}")
    }
  }
}

test "portable trims trailing dots and spaces" {
  match sanitize_portable_filename("report.pdf.") {
    Ok(r) => {
      inspect(r.safe(), content="report.pdf")
      assert_true(has_key(r.issues(), "trimmed-trailing-char"))
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
  match sanitize_portable_filename("report ") {
    Ok(r) => inspect(r.safe(), content="report")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "portable truncates to the policy maximum length" {
  let p = FilenamePolicy::portable().with_max_length(12)
  match sanitize_filename("a-very-long-filename.txt", p) {
    Ok(r) => {
      inspect(r.safe(), content="a-very-long-")
      inspect(r.safe().char_length(), content="12")
      assert_true(has_key(r.issues(), "truncated-to-max-length"))
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "truncation cannot reintroduce a trailing dot" {
  // "12345.67890" truncated to 6 cuts just past the dot, leaving "12345."
  // which must be trimmed again so the result is stable.
  let p = FilenamePolicy::portable().with_max_length(6)
  match sanitize_filename("12345.67890", p) {
    Ok(r) => {
      inspect(r.safe(), content="12345")
      assert_true(has_key(r.issues(), "truncated-to-max-length"))
      assert_true(has_key(r.issues(), "trimmed-trailing-char"))
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "truncation cannot reintroduce a reserved name" {
  let p = FilenamePolicy::portable().with_max_length(3)
  match sanitize_filename("CONxxxx", p) {
    Ok(r) => {
      inspect(r.safe(), content="_CON")
      assert_true(has_key(r.issues(), "truncated-to-max-length"))
      assert_true(has_key(r.issues(), "prefixed-reserved-name"))
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "sanitising an empty name errors" {
  match sanitize_portable_filename("") {
    Ok(_) => assert_true(false, msg="expected an error")
    Err(e) => {
      inspect(e.stage().to_string(), content="FilenamePolicy")
      inspect(e.kind().to_string(), content="UnsafeFilename")
    }
  }
}

test "sanitising an all-dot name never yields an empty result" {
  // "..." trims to nothing; the sanitizer falls back to a single underscore
  // so a non-empty input always produces a usable safe name.
  match sanitize_portable_filename("...") {
    Ok(r) => {
      inspect(r.safe(), content="_")
      assert_false(r.safe() == "" || r.safe() == "." || r.safe() == "..")
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "windows-like keeps non-ASCII and removes forbidden characters" {
  let p = FilenamePolicy::windows_like()
  match sanitize_filename("café.txt", p) {
    Ok(r) => {
      inspect(r.safe(), content="café.txt")
      assert_false(r.changed())
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
  match sanitize_filename("a<b>:c*d?e", p) {
    Ok(r) => inspect(r.safe(), content="a_b__c_d_e")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "posix-like replaces only the slash and NUL" {
  let p = FilenamePolicy::posix_like()
  match sanitize_filename("a/b\nc", p) {
    Ok(r) => {
      inspect(r.safe(), content="a_b\nc")
      assert_true(has_key(r.issues(), "replaced-path-separator"))
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
  match sanitize_filename("café.txt", p) {
    Ok(r) => {
      inspect(r.safe(), content="café.txt")
      assert_false(r.changed())
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "windows-like defuses reserved names but keeps non-ASCII" {
  let p = FilenamePolicy::windows_like()
  match sanitize_filename("CON.txt", p) {
    Ok(r) => {
      inspect(r.safe(), content="_CON.txt")
      assert_true(has_key(r.issues(), "prefixed-reserved-name"))
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "posix-like does not defuse reserved names" {
  let p = FilenamePolicy::posix_like()
  match sanitize_filename("CON.txt", p) {
    Ok(r) => inspect(r.safe(), content="CON.txt")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "replacement is per character, never transliteration" {
  match sanitize_portable_filename("日本") {
    Ok(r) => inspect(r.safe(), content="__")
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "sanitising the sanitised name is a no-op (explicit)" {
  let inputs = ["report.pdf", "my report.pdf", "../x", "CON", "a.b.", "a b c.txt"]
  for name in inputs {
    match sanitize_portable_filename(name) {
      Ok(first) => {
        match sanitize_portable_filename(first.safe()) {
          Ok(second) =>
            assert_true(
              second.safe() == first.safe(),
              msg="\{name}: \{first.safe()} -> \{second.safe()}",
            )
          Err(e) => assert_true(false, msg="second sanitise failed for \{first.safe()}: \{e.to_display()}")
        }
      }
      Err(_) => () // inputs that error (none here) are skipped
    }
  }
}

test "1000+ sanitizer invariants across all profiles" {
  let rng = prng(801)
  let failures : Array[String] = []
  let mut cases = 0
  for _i = 0; _i < 1300; _i = _i + 1 {
    // Random name: mix of ASCII file characters and non-ASCII.
    let mut name = ""
    let use_unicode = rng.bool()
    if use_unicode {
      name = random_unicode_name(rng, 30)
    } else {
      name = random_string_from(rng, FILE_ALPHABET, rng.below(40))
    }
    // Random policy.
    let profile = rng.below(3)
    let cap = 1 + rng.below(40)
    let mut policy = match profile {
      0 => FilenamePolicy::portable()
      1 => FilenamePolicy::windows_like()
      _ => FilenamePolicy::posix_like()
    }
    policy = policy.with_max_length(cap)
    if rng.bool() {
      policy = policy.with_windows_reserved(WindowsReservedPolicy::disabled())
    }
    match sanitize_filename(name, policy) {
      Err(_) => ()
      Ok(result) => {
        cases = cases + 1
        let safe = result.safe()
        // Invariant 1: never empty.
        if safe.char_length() == 0 {
          failures.push("empty safe for \{name}")
        }
        // Invariant 2: never a path separator.
        if !no_separator(safe) {
          failures.push("separator survived for \{name} -> \{safe}")
        }
        // Invariant 3: never "." or "..".
        if safe == "." || safe == ".." {
          failures.push("dot name survived for \{name} -> \{safe}")
        }
        // Invariant 4: bounded length.
        if safe.char_length() > cap {
          failures.push("over-long safe for \{name} -> \{safe}")
        }
        // Invariant 5: profile-safe characters.
        if !profile_chars_ok(policy.profile(), safe) {
          failures.push("unsafe chars for \{policy.profile().to_string()} in \{name} -> \{safe}")
        }
        // Invariant 6: idempotency.
        match sanitize_filename(safe, policy) {
          Ok(again) =>
            if again.safe() != safe {
              failures.push("non-idempotent: \{name} -> \{safe} -> \{again.safe()}")
            }
          Err(e) => failures.push("re-sanitise failed for \{name} -> \{safe}: \{e.to_display()}")
        }
      }
    }
  }
  assert_true(cases >= 1000, msg="only \{cases} cases ran; the sweep should exceed 1000")
  assert_true(failures.length() == 0, msg="failures: \{show_strings(failures)}")
}

// --- invariant helpers -----------------------------------------------------

fn no_separator(s : String) -> Bool {
  for ch in s {
    if ch == '/' || ch == '\\' {
      return false
    }
  }
  true
}

// Whether every code point of `s` survives the profile's character rule.
fn profile_chars_ok(profile : PolicyProfile, s : String) -> Bool {
  for ch in s {
    if !profile_safe_char_for_test(profile, ch) {
      return false
    }
  }
  true
}

// The profile character rule, mirrored from the library for the invariants.
fn profile_safe_char_for_test(profile : PolicyProfile, ch : Char) -> Bool {
  match profile {
    Portable => {
      let v = ch.to_int()
      (v >= 48 && v <= 57) || (v >= 65 && v <= 90) || (v >= 97 && v <= 122) ||
        ch == '.' || ch == '_' || ch == '-'
    }
    WindowsLike => {
      let v = ch.to_int()
      if v < 32 || v == 127 {
        return false
      }
      ch != '<' && ch != '>' && ch != ':' && ch != '"' && ch != '/' && ch != '\\' &&
        ch != '|' && ch != '?' && ch != '*'
    }
    PosixLike => ch != '/' && ch.to_int() != 0
  }
}
