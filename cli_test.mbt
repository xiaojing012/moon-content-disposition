// cli_test.mbt — The `disposition-tool` command surface (pure, JSON out).

test "version command" {
  let out = run_cli(["version"])
  inspect(out, content="{\"ok\":true,\"command\":\"version\",\"version\":\"0.1.0\"}")
}

test "help command lists the eleven commands" {
  let out = run_cli(["help"])
  assert_true(out.contains("\"ok\":true"))
  assert_true(out.contains("\"commands\":[\"parse\",\"serialize\",\"canonicalize\",\"resolve\",\"sanitize\",\"generate\",\"audit\",\"limits\",\"profiles\",\"version\",\"help\"]"))
}

test "no command is an error" {
  let out = run_cli([])
  assert_true(out.contains("\"ok\":false"))
  assert_true(out.contains("\"command\":\"no-command\""))
}

test "unknown command is an error" {
  let out = run_cli(["frobnicate"])
  assert_true(out.contains("\"ok\":false"))
  assert_true(out.contains("unknown-command"))
}

test "parse command renders the model" {
  let out = run_cli(["parse", "attachment; filename=report.pdf"])
  inspect(
    out,
    content="{\"ok\":true,\"command\":\"parse\",\"disposition_type\":\"attachment\",\"parameters\":[{\"name\":\"filename\",\"value\":\"report.pdf\",\"form\":\"token\"}]}",
  )
}

test "parse command renders extended values" {
  let out = run_cli(["parse", "attachment; filename*=UTF-8''caf%C3%A9"])
  assert_true(out.contains("\"form\":\"extended\""))
  assert_true(out.contains("\"value\":\"café\""))
  assert_true(out.contains("\"charset\":\"UTF-8\""))
  assert_true(out.contains("\"language\":null"))
}

test "parse command reports errors as JSON" {
  let out = run_cli(["parse", ""])
  assert_true(out.contains("\"ok\":false"))
  assert_true(out.contains("\"stage\":\"Input\""))
  assert_true(out.contains("\"kind\":\"EmptyInput\""))
}

test "serialize command" {
  let out = run_cli(["serialize", "ATTACHMENT; FILE=PDF"])
  assert_true(out.contains("\"ok\":true"))
  assert_true(out.contains("\"value\":\"attachment; file=PDF\""))
}

test "canonicalize command" {
  let out = run_cli(["canonicalize", "attachment; filename*=UTF-8''%E4%B8%AD; filename=fallback.txt"])
  assert_true(out.contains("\"value\":\"attachment; filename=fallback.txt; filename*=UTF-8''%E4%B8%AD\""))
}

test "resolve command" {
  let out = run_cli(["resolve", "attachment; filename=report.pdf"])
  assert_true(out.contains("\"filename\":\"report.pdf\""))
  assert_true(out.contains("\"source\":\"filename\""))
  assert_true(out.contains("\"fallback\":false"))
  assert_true(out.contains("\"warnings\":[]"))
}

test "resolve command reports warnings" {
  let out = run_cli(["resolve", "attachment; filename=\"../x\""])
  assert_true(out.contains("\"warnings\":[\"contains-path-separator\"]"))
}

test "resolve command reports errors" {
  let out = run_cli(["resolve", "attachment"])
  assert_true(out.contains("\"kind\":\"InvalidFilename\""))
}

test "sanitize command defaults to portable" {
  let out = run_cli(["sanitize", "a b.txt"])
  assert_true(out.contains("\"original\":\"a b.txt\""))
  assert_true(out.contains("\"safe\":\"a_b.txt\""))
  assert_true(out.contains("\"changed\":true"))
  assert_true(out.contains("\"issues\":[\"replaced-unsafe-character\"]"))
}

test "sanitize command accepts a profile" {
  let out = run_cli(["sanitize", "café.txt", "windows-like"])
  assert_true(out.contains("\"safe\":\"café.txt\""))
  assert_true(out.contains("\"changed\":false"))
  let out2 = run_cli(["sanitize", "CON", "portable"])
  assert_true(out2.contains("\"safe\":\"_CON\""))
}

test "sanitize command rejects a bad profile" {
  let out = run_cli(["sanitize", "x", "bogus"])
  assert_true(out.contains("\"ok\":false"))
  assert_true(out.contains("profile must be"))
}

test "sanitize command escapes JSON in the output" {
  let out = run_cli(["sanitize", "a\"b"])
  assert_true(out.contains("\"original\":\"a\\\"b\""))
  assert_true(out.contains("\"safe\":\"a_b\""))
}

test "generate command" {
  let out = run_cli(["generate", "attachment", "café.txt"])
  assert_true(out.contains("\"value\":\"attachment; filename=\\\"café.txt\\\"; filename*=UTF-8''caf%C3%A9.txt\""))
  let out2 = run_cli(["generate", "inline", "a"])
  assert_true(out2.contains("\"value\":\"inline; filename=\\\"a\\\"\""))
}

test "generate command rejects a bad disposition type" {
  let out = run_cli(["generate", "weird", "a"])
  assert_true(out.contains("\"ok\":false"))
  assert_true(out.contains("'attachment' or 'inline'"))
}

test "generate command rejects control characters" {
  let out = run_cli(["generate", "attachment", "a\nb"])
  assert_true(out.contains("\"ok\":false"))
  assert_true(out.contains("\"kind\":\"InvalidControlCharacter\""))
}

test "audit command renders issues" {
  let out = run_cli(["audit", "attachment; filename=\"../x\""])
  assert_true(out.contains("\"ok\":true"))
  assert_true(out.contains("\"severity\":\"high\""))
  assert_true(out.contains("\"kind\":\"path-separator-in-filename\""))
}

test "audit command reports parse errors" {
  // '!' alone is actually a valid extension disposition type token, so a
  // missing type (a leading ';') is used to force InvalidDispositionType.
  let out = run_cli(["audit", "; filename=x"])
  assert_true(out.contains("\"ok\":false"))
  assert_true(out.contains("\"kind\":\"InvalidDispositionType\""))
}

test "limits command defaults to default preset" {
  let out = run_cli(["limits"])
  assert_true(out.contains("\"preset\":\"default\""))
  assert_true(out.contains("\"max_input_bytes\":1048576"))
  assert_true(out.contains("\"max_parameters\":256"))
}

test "limits command accepts a preset" {
  let out = run_cli(["limits", "strict"])
  assert_true(out.contains("\"preset\":\"strict\""))
  assert_true(out.contains("\"max_parameters\":32"))
  let out2 = run_cli(["limits", "permissive"])
  assert_true(out2.contains("\"max_input_bytes\":67108864"))
}

test "limits command rejects a bad preset" {
  let out = run_cli(["limits", "bogus"])
  assert_true(out.contains("\"ok\":false"))
}

test "profiles command" {
  let out = run_cli(["profiles"])
  assert_true(out.contains("\"profiles\":["))
  assert_true(out.contains("\"name\":\"portable\""))
  assert_true(out.contains("\"name\":\"posix-like\""))
}

test "commands are case-insensitive" {
  let out = run_cli(["VERSION"])
  assert_true(out.contains("\"version\":\"0.1.0\""))
}
