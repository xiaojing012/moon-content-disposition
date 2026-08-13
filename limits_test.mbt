// limits_test.mbt — Resource limits: presets and per-field bounds.

// A helper to build strings of an exact byte length.
fn repeat_str(s : String, n : Int) -> String {
  let sb = StringBuilder()
  for _i = 0; _i < n; _i = _i + 1 {
    sb.write_string(s)
  }
  sb.to_string()
}

test "default limits" {
  let l = Limits::default()
  inspect(l.max_input_bytes(), content="1048576")
  inspect(l.max_parameters(), content="256")
  inspect(l.max_parameter_name_bytes(), content="256")
  inspect(l.max_parameter_value_bytes(), content="8192")
  inspect(l.max_filename_bytes(), content="1024")
  inspect(l.max_extended_value_bytes(), content="8192")
  inspect(l.max_context_bytes(), content="80")
}

test "strict limits" {
  let l = Limits::strict()
  inspect(l.max_input_bytes(), content="16384")
  inspect(l.max_parameters(), content="32")
  inspect(l.max_parameter_name_bytes(), content="64")
  inspect(l.max_parameter_value_bytes(), content="1024")
  inspect(l.max_filename_bytes(), content="255")
  inspect(l.max_extended_value_bytes(), content="1024")
}

test "permissive limits" {
  let l = Limits::permissive()
  inspect(l.max_input_bytes(), content="67108864")
  inspect(l.max_parameters(), content="4096")
  assert_true(l.max_parameter_value_bytes() >= l.max_parameter_name_bytes())
}

test "the module-level context bound matches default" {
  inspect(max_context_bytes(), content="80")
}

test "a parameter name at the strict bound is accepted" {
  let name = "n" + repeat_str("a", 63) // 64 bytes, exactly max_parameter_name_bytes
  let options = ParseOptions::strict()
  match parse_content_disposition_with_options("attachment; \{name}=v", options) {
    Ok(_) => assert_true(true)
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "a parameter name above the strict bound is rejected" {
  let name = "n" + repeat_str("a", 64) // 65 bytes
  let options = ParseOptions::strict()
  match parse_content_disposition_with_options("attachment; \{name}=v", options) {
    Ok(_) => assert_true(false, msg="expected a limit error")
    Err(e) => {
      inspect(e.stage().to_string(), content="Limit")
      inspect(e.kind().to_string(), content="LimitExceeded")
    }
  }
}

test "a parameter value at the strict bound is accepted" {
  let value = repeat_str("a", 1024)
  let options = ParseOptions::strict()
  match parse_content_disposition_with_options("attachment; size=\{value}", options) {
    Ok(_) => assert_true(true)
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "a parameter value above the strict bound is rejected" {
  let value = repeat_str("a", 1025)
  let options = ParseOptions::strict()
  match parse_content_disposition_with_options("attachment; size=\{value}", options) {
    Ok(_) => assert_true(false, msg="expected a limit error")
    Err(e) => {
      inspect(e.stage().to_string(), content="Limit")
      inspect(e.kind().to_string(), content="LimitExceeded")
    }
  }
}

test "an extended value above the strict bound is rejected" {
  let value = repeat_str("a", 1025)
  let options = ParseOptions::strict()
  match parse_content_disposition_with_options("attachment; filename*=UTF-8''\{value}", options) {
    Ok(_) => assert_true(false, msg="expected a limit error")
    Err(e) => {
      inspect(e.stage().to_string(), content="Limit")
      inspect(e.kind().to_string(), content="LimitExceeded")
    }
  }
}

test "an extended value at the strict bound is accepted" {
  let value = repeat_str("a", 1024)
  let options = ParseOptions::strict()
  match parse_content_disposition_with_options("attachment; filename*=UTF-8''\{value}", options) {
    Ok(_) => assert_true(true)
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "too many parameters are rejected at the strict bound" {
  let sb = StringBuilder()
  sb.write_string("attachment")
  for i = 0; i < 33; i = i + 1 {
    sb.write_string("; p\{i}=x")
  }
  let options = ParseOptions::strict()
  match parse_content_disposition_with_options(sb.to_string(), options) {
    Ok(_) => assert_true(false, msg="expected a limit error")
    Err(e) => {
      inspect(e.stage().to_string(), content="Limit")
      inspect(e.kind().to_string(), content="LimitExceeded")
    }
  }
}

test "permissive limits accept what strict rejects" {
  let value = repeat_str("a", 2000)
  match parse_content_disposition_with_options(
    "attachment; size=\{value}",
    ParseOptions::permissive(),
  ) {
    Ok(_) => assert_true(true)
    Err(e) => assert_true(false, msg="unexpected error: \{e.to_display()}")
  }
}

test "an input over max_input_bytes is rejected at the Input stage" {
  let big = repeat_str("a", 17000) // 17 KiB > strict max_input_bytes (16 KiB)
  let options = ParseOptions::strict()
  match parse_content_disposition_with_options("attachment; size=\{big}", options) {
    Ok(_) => assert_true(false, msg="expected a limit error")
    Err(e) => {
      inspect(e.stage().to_string(), content="Input")
      inspect(e.kind().to_string(), content="LimitExceeded")
    }
  }
}
