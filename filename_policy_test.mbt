// filename_policy_test.mbt — The three sanitisation profiles and policy knobs.

test "the default policy is portable" {
  let p = FilenamePolicy::default()
  inspect(p.profile().to_string(), content="portable")
  inspect(p.max_length(), content="255")
  assert_false(p.extension().is_enabled())
  assert_true(p.windows_reserved().is_enabled())
}

test "the portable preset" {
  let p = FilenamePolicy::portable()
  inspect(p.profile().to_string(), content="portable")
  assert_true(p.windows_reserved().is_enabled())
}

test "the windows-like preset" {
  let p = FilenamePolicy::windows_like()
  inspect(p.profile().to_string(), content="windows-like")
  assert_true(p.windows_reserved().is_enabled())
}

test "the posix-like preset" {
  let p = FilenamePolicy::posix_like()
  inspect(p.profile().to_string(), content="posix-like")
  assert_false(p.windows_reserved().is_enabled())
}

test "profiles have stable programmatic names" {
  inspect(FilenamePolicy::portable().profile().to_string(), content="portable")
  inspect(FilenamePolicy::windows_like().profile().to_string(), content="windows-like")
  inspect(FilenamePolicy::posix_like().profile().to_string(), content="posix-like")
}

test "with_max_length changes only the length cap" {
  let p = FilenamePolicy::portable().with_max_length(64)
  inspect(p.max_length(), content="64")
  inspect(p.profile().to_string(), content="portable")
  assert_true(p.windows_reserved().is_enabled())
}

test "with_extension enables extension auditing" {
  let p = FilenamePolicy::portable().with_extension(
    ExtensionPolicy::enabled(["pdf", "txt"], ["exe"]),
  )
  assert_true(p.extension().is_enabled())
  expect_same_strings(p.extension().allow_list(), ["pdf", "txt"])
  expect_same_strings(p.extension().deny_list(), ["exe"])
}

test "with_windows_reserved disables reserved-name defusing" {
  let p = FilenamePolicy::portable().with_windows_reserved(WindowsReservedPolicy::disabled())
  assert_false(p.windows_reserved().is_enabled())
}

test "extension policy matching is case-insensitive with or without a dot" {
  let p = FilenamePolicy::portable().with_extension(ExtensionPolicy::enabled([".PDF"], [".exe"]))
  match sanitize_filename("report.PDF", p) {
    Ok(r) => {
      inspect(r.safe(), content="report.PDF")
      // PDF is allowed (matched case-insensitively); no issue is raised.
      assert_true(!has_key(r.issues(), "extension-not-in-allow-list"))
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "extension auditing records a denied extension" {
  let p = FilenamePolicy::portable().with_extension(ExtensionPolicy::enabled([], ["exe"]))
  match sanitize_filename("install.exe", p) {
    Ok(r) => {
      inspect(r.safe(), content="install.exe")
      assert_true(has_key(r.issues(), "denied-extension"))
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "extension auditing records a missing allow-list match" {
  let p = FilenamePolicy::portable().with_extension(ExtensionPolicy::enabled(["pdf"], []))
  match sanitize_filename("readme.txt", p) {
    Ok(r) => assert_true(has_key(r.issues(), "extension-not-in-allow-list"))
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
  match sanitize_filename("readme.pdf", p) {
    Ok(r) => assert_true(!has_key(r.issues(), "extension-not-in-allow-list"))
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "extension auditing ignores files without a dot" {
  let p = FilenamePolicy::portable().with_extension(ExtensionPolicy::enabled([], ["exe"]))
  match sanitize_filename("Makefile", p) {
    Ok(r) => {
      assert_true(r.safe() == "Makefile")
      assert_true(!has_key(r.issues(), "denied-extension"))
    }
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}
