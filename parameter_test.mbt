// parameter_test.mbt — Parameter parsing and extended-parameter detection.

// Captures the (stage, kind) of a failed parameter parse, returning ("", "")
// when the parse succeeds.
fn param_error(input : String, limits : Limits) -> (String, String) {
  let s = Scanner::new(input)
  match parse_parameter(s, limits, ParseOptions::strict().mode(), ParseCollector::new()) {
    Ok(_) => ("", "")
    Err(e) => (e.stage().to_string(), e.kind().to_string())
  }
}

test "parse_parameter reads a token value" {
  let s = Scanner::new("size=42")
  let p = match parse_parameter(s, Limits::default(), ParseOptions::strict().mode(), ParseCollector::new()) {
    Ok(p) => p
    Err(e) => abort("unexpected error: \{e.to_display()}")
  }
  inspect(p.name(), content="size")
  match p.value() {
    Token(v) => inspect(v, content="42")
    _ => assert_true(false, msg="expected a token value")
  }
  inspect(s.position(), content="7")
}

test "parse_parameter reads a quoted value" {
  let s = Scanner::new("name=\"a b\"")
  let p = match parse_parameter(s, Limits::default(), ParseOptions::strict().mode(), ParseCollector::new()) {
    Ok(p) => p
    Err(e) => abort("unexpected error: \{e.to_display()}")
  }
  match p.value() {
    Quoted(v) => inspect(v, content="a b")
    _ => assert_true(false, msg="expected a quoted value")
  }
}

test "parse_parameter tolerates ows around the equals" {
  let s = Scanner::new("size = 42")
  let p = match parse_parameter(s, Limits::default(), ParseOptions::strict().mode(), ParseCollector::new()) {
    Ok(p) => p
    Err(e) => abort("unexpected error: \{e.to_display()}")
  }
  match p.value() {
    Token(v) => inspect(v, content="42")
    _ => assert_true(false, msg="expected a token value")
  }
}

test "parse_parameter rejects a missing name" {
  let (stage, kind) = param_error("; size=1", Limits::default())
  inspect(stage, content="ParameterName")
  inspect(kind, content="ExpectedToken")
}

test "parse_parameter rejects a missing equals" {
  let (stage, kind) = param_error("size 42", Limits::default())
  inspect(stage, content="ParameterName")
  inspect(kind, content="MissingEquals")
}

test "parse_parameter rejects a missing value" {
  let (_, kind) = param_error("size=", Limits::default())
  inspect(kind, content="MissingParameterValue")
}

test "parse_parameter reads an extended value parameter" {
  let s = Scanner::new("filename*=UTF-8''caf%C3%A9")
  let p = match parse_parameter(s, Limits::default(), ParseOptions::strict().mode(), ParseCollector::new()) {
    Ok(p) => p
    Err(e) => abort("unexpected error: \{e.to_display()}")
  }
  inspect(p.name(), content="filename*")
  assert_true(p.is_extended())
  match p.value().extended() {
    Some(ev) => inspect(ev.value(), content="café")
    None => assert_true(false, msg="expected an extended value")
  }
}

test "parse_parameter enforces the name length limit" {
  let long_name = StringBuilder()
  for _i = 0; _i < 100; _i = _i + 1 {
    long_name.write_string("x")
  }
  let (stage, kind) = param_error(long_name.to_string() + "=v", Limits::strict())
  inspect(stage, content="Limit")
  inspect(kind, content="LimitExceeded")
}

test "is_extended_param_name detects the star suffix" {
  assert_true(is_extended_param_name("filename*"))
  assert_true(is_extended_param_name("x*"))
  assert_false(is_extended_param_name("filename"))
  assert_false(is_extended_param_name("*"))
  assert_false(is_extended_param_name(""))
}
