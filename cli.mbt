// cli.mbt — Command-line dispatch for the `disposition-tool` executable.
//
// The whole CLI lives in the library as pure functions that return JSON
// strings, so every command is unit-testable and the `cmd/disposition-tool`
// package is a thin wrapper that prints `run_cli`'s output. No command ever
// unwraps: every `Result` is rendered either as a success JSON object or as
// an error JSON object carrying the structured `DispositionError`.
//
// Every command's output is a single JSON object with an `"ok"` boolean and
// a `"command"` field:
//
//   - `parse <value>`            the parsed model
//   - `serialize <value>`        parse then canonical serialisation
//   - `canonicalize <value>`     parse then canonicalise
//   - `resolve <value>`          parse then resolve the download filename
//   - `sanitize <name> [profile]` sanitise a filename under a profile
//   - `generate <type> <name>`   generate an attachment/inline value
//   - `audit <value>`            parse and audit
//   - `limits [preset]`          show the resource limits of a preset
//   - `profiles`                 describe the sanitisation profiles
//   - `version`                  the library version string
//   - `help`                     this usage message

///|
/// Runs the CLI with the given arguments (excluding the program name) and
/// returns the JSON output. Never raises, never unwraps.
pub fn run_cli(args : Array[String]) -> String {
  if args.is_empty() {
    return json_error("no-command", "no command given; try 'help'")
  }
  let command = args[0].to_lower()
  match command {
    "parse" => cmd_parse(args[1:].to_owned())
    "serialize" => cmd_serialize(args[1:].to_owned())
    "canonicalize" => cmd_canonicalize(args[1:].to_owned())
    "resolve" => cmd_resolve(args[1:].to_owned())
    "sanitize" => cmd_sanitize(args[1:].to_owned())
    "generate" => cmd_generate(args[1:].to_owned())
    "audit" => cmd_audit(args[1:].to_owned())
    "limits" => cmd_limits(args[1:].to_owned())
    "profiles" => cmd_profiles()
    "version" => cmd_version()
    "help" => cmd_help()
    _ => json_error("unknown-command", "unknown command '\{command}'; try 'help'")
  }
}

fn cmd_parse(args : Array[String]) -> String {
  match arg_join(args) {
    Err(msg) => json_error("usage", msg)
    Ok(input) => {
      match parse_content_disposition(input) {
        Ok(cd) => {
          let sb = StringBuilder()
          sb.write_string("{\"ok\":true,\"command\":\"parse\",\"disposition_type\":")
          sb.write_string(json_string(cd.disposition_type().to_lower_name()))
          sb.write_string(",\"parameters\":[")
          for i = 0; i < cd.parameters().length(); i = i + 1 {
            if i > 0 {
              sb.write_string(",")
            }
            sb.write_string(parameter_json(cd.parameters()[i]))
          }
          sb.write_string("]}")
          sb.to_string()
        }
        Err(e) => json_error_result(e, "parse")
      }
    }
  }
}

fn cmd_serialize(args : Array[String]) -> String {
  match arg_join(args) {
    Err(msg) => json_error("usage", msg)
    Ok(input) => {
      match parse_content_disposition(input) {
        Ok(cd) => {
          match serialize_content_disposition(cd) {
            Ok(s) => json_ok_str("serialize", "value", s)
            Err(e) => json_error_result(e, "serialize")
          }
        }
        Err(e) => json_error_result(e, "serialize")
      }
    }
  }
}

fn cmd_canonicalize(args : Array[String]) -> String {
  match arg_join(args) {
    Err(msg) => json_error("usage", msg)
    Ok(input) => {
      match canonicalize_content_disposition(input) {
        Ok(s) => json_ok_str("canonicalize", "value", s)
        Err(e) => json_error_result(e, "canonicalize")
      }
    }
  }
}

fn cmd_resolve(args : Array[String]) -> String {
  match arg_join(args) {
    Err(msg) => json_error("usage", msg)
    Ok(input) => {
      match parse_content_disposition(input) {
        Ok(cd) => {
          match resolve_filename(cd) {
            Ok(sel) => {
              let sb = StringBuilder()
              sb.write_string("{\"ok\":true,\"command\":\"resolve\",\"filename\":")
              sb.write_string(json_string(sel.selected()))
              sb.write_string(",\"source\":")
              sb.write_string(json_string(filename_source_name(sel.source())))
              sb.write_string(",\"fallback\":")
              sb.write_string(json_bool(sel.fallback()))
              sb.write_string(",\"warnings\":[")
              write_string_array(sb, sel.warnings())
              sb.write_string("]}")
              sb.to_string()
            }
            Err(e) => json_error_result(e, "resolve")
          }
        }
        Err(e) => json_error_result(e, "resolve")
      }
    }
  }
}

fn cmd_sanitize(args : Array[String]) -> String {
  if args.is_empty() {
    return json_error("usage", "sanitize needs a filename")
  }
  let name = args[0]
  let policy = match profile_arg(args, 1) {
    Ok(p) => p
    Err(msg) => return json_error("usage", msg)
  }
  match sanitize_filename(name, policy) {
    Ok(r) => {
      let sb = StringBuilder()
      sb.write_string("{\"ok\":true,\"command\":\"sanitize\",\"original\":")
      sb.write_string(json_string(r.original()))
      sb.write_string(",\"safe\":")
      sb.write_string(json_string(r.safe()))
      sb.write_string(",\"changed\":")
      sb.write_string(json_bool(r.changed()))
      sb.write_string(",\"issues\":[")
      write_string_array(sb, r.issues())
      sb.write_string("]}")
      sb.to_string()
    }
    Err(e) => json_error_result(e, "sanitize")
  }
}

fn cmd_generate(args : Array[String]) -> String {
  if args.length() < 2 {
    return json_error("usage", "generate needs a disposition type and a filename")
  }
  let dtype = args[0].to_lower()
  let name = args[1]
  let result = match dtype {
    "attachment" => generate_attachment(name)
    "inline" => generate_inline(name)
    _ => return json_error("usage", "disposition type must be 'attachment' or 'inline'")
  }
  match result {
    Ok(s) => json_ok_str("generate", "value", s)
    Err(e) => json_error_result(e, "generate")
  }
}

fn cmd_audit(args : Array[String]) -> String {
  match arg_join(args) {
    Err(msg) => json_error("usage", msg)
    Ok(input) => {
      match audit_header(input) {
        Ok(report) => {
          let sb = StringBuilder()
          sb.write_string("{\"ok\":true,\"command\":\"audit\",\"issues\":[")
          for i = 0; i < report.issues().length(); i = i + 1 {
            if i > 0 {
              sb.write_string(",")
            }
            let issue = report.issues()[i]
            sb.write_string("{\"severity\":")
            sb.write_string(json_string(issue.severity().to_string()))
            sb.write_string(",\"kind\":")
            sb.write_string(json_string(issue.kind().to_string()))
            sb.write_string(",\"parameter\":")
            sb.write_string(json_string(issue.parameter()))
            sb.write_string(",\"message\":")
            sb.write_string(json_string(issue.message()))
            sb.write_string("}")
          }
          sb.write_string("]}")
          sb.to_string()
        }
        Err(e) => json_error_result(e, "audit")
      }
    }
  }
}

fn cmd_limits(args : Array[String]) -> String {
  let limits = if args.is_empty() {
    Limits::default()
  } else {
    match args[0].to_lower() {
      "strict" => Limits::strict()
      "permissive" => Limits::permissive()
      "default" => Limits::default()
      _ => return json_error("usage", "limits preset must be default, strict or permissive")
    }
  }
  let sb = StringBuilder()
  sb.write_string("{\"ok\":true,\"command\":\"limits\",\"preset\":")
  sb.write_string(json_string(if args.is_empty() { "default" } else { args[0].to_lower() }))
  sb.write_string(",\"max_input_bytes\":")
  sb.write_string(limits.max_input_bytes().to_string())
  sb.write_string(",\"max_parameters\":")
  sb.write_string(limits.max_parameters().to_string())
  sb.write_string(",\"max_parameter_name_bytes\":")
  sb.write_string(limits.max_parameter_name_bytes().to_string())
  sb.write_string(",\"max_parameter_value_bytes\":")
  sb.write_string(limits.max_parameter_value_bytes().to_string())
  sb.write_string(",\"max_filename_bytes\":")
  sb.write_string(limits.max_filename_bytes().to_string())
  sb.write_string(",\"max_extended_value_bytes\":")
  sb.write_string(limits.max_extended_value_bytes().to_string())
  sb.write_string(",\"max_context_bytes\":")
  sb.write_string(limits.max_context_bytes().to_string())
  sb.write_string("}")
  sb.to_string()
}

fn cmd_profiles() -> String {
  let sb = StringBuilder()
  sb.write_string("{\"ok\":true,\"command\":\"profiles\",\"profiles\":[")
  let names = ["portable", "windows-like", "posix-like"]
  for i = 0; i < names.length(); i = i + 1 {
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string("{\"name\":")
    sb.write_string(json_string(names[i]))
    sb.write_string(",\"max_length\":\"255\"")
    sb.write_string(",\"reserved_names_defused\":")
    sb.write_string(if names[i] == "posix-like" { "false" } else { "true" })
    sb.write_string("}")
  }
  sb.write_string("]}")
  sb.to_string()
}

fn cmd_version() -> String {
  "{\"ok\":true,\"command\":\"version\",\"version\":\{json_string(library_version())}}"
}

fn cmd_help() -> String {
  "{\"ok\":true,\"command\":\"help\",\"usage\":\"disposition-tool <command> [args...]\",\"commands\":[\"parse\",\"serialize\",\"canonicalize\",\"resolve\",\"sanitize\",\"generate\",\"audit\",\"limits\",\"profiles\",\"version\",\"help\"]}"
}

// --- helpers ---------------------------------------------------------------

// Joins arguments into one input string (the header value may contain
// spaces). Empty input is an error: a parse of "" would fail anyway, but
// failing here keeps the usage message clear.
fn arg_join(args : Array[String]) -> Result[String, String] {
  if args.is_empty() {
    return Err("this command needs a header value argument")
  }
  let sb = StringBuilder()
  for i = 0; i < args.length(); i = i + 1 {
    if i > 0 {
      sb.write_string(" ")
    }
    sb.write_string(args[i])
  }
  Ok(sb.to_string())
}

// The policy for a `sanitize` profile argument (index `i`), defaulting to
// portable.
fn profile_arg(args : Array[String], i : Int) -> Result[FilenamePolicy, String] {
  if i >= args.length() || args[i] == "" {
    return Ok(FilenamePolicy::portable())
  }
  match args[i].to_lower() {
    "portable" => Ok(FilenamePolicy::portable())
    "windows-like" => Ok(FilenamePolicy::windows_like())
    "posix-like" => Ok(FilenamePolicy::posix_like())
    _ => Err("profile must be portable, windows-like or posix-like")
  }
}

// The JSON object for one parameter.
fn parameter_json(p : DispositionParameter) -> String {
  let sb = StringBuilder()
  sb.write_string("{\"name\":")
  sb.write_string(json_string(p.name()))
  sb.write_string(",\"value\":")
  match p.value() {
    Token(v) => {
      sb.write_string(json_string(v))
      sb.write_string(",\"form\":\"token\"")
    }
    Quoted(v) => {
      sb.write_string(json_string(v))
      sb.write_string(",\"form\":\"quoted\"")
    }
    Extended(ev) => {
      sb.write_string(json_string(ev.value()))
      sb.write_string(",\"form\":\"extended\",\"charset\":")
      sb.write_string(json_string(ev.charset()))
      sb.write_string(",\"language\":")
      match ev.language() {
        Some(l) => sb.write_string(json_string(l))
        None => sb.write_string("null")
      }
    }
  }
  sb.write_string("}")
  sb.to_string()
}

// Renders a structured error as an error JSON object.
fn json_error_result(e : DispositionError, command : String) -> String {
  let sb = StringBuilder()
  sb.write_string("{\"ok\":false,\"command\":")
  sb.write_string(json_string(command))
  sb.write_string(",\"error\":{\"stage\":")
  sb.write_string(json_string(e.stage().to_string()))
  sb.write_string(",\"kind\":")
  sb.write_string(json_string(e.kind().to_string()))
  sb.write_string(",\"offset\":")
  sb.write_string(e.offset().to_string())
  sb.write_string(",\"context\":")
  sb.write_string(json_string(e.context()))
  sb.write_string("}}")
  sb.to_string()
}

// A generic error JSON object.
fn json_error(command : String, message : String) -> String {
  "{\"ok\":false,\"command\":\{json_string(command)},\"error\":\{json_string(message)}}"
}

// A success JSON object with one string field.
fn json_ok_str(command : String, key : String, value : String) -> String {
  "{\"ok\":true,\"command\":\{json_string(command)},\{json_string(key)}:\{json_string(value)}}"
}

// Writes `["a","b"]` (or `[]`) to the builder.
fn write_string_array(sb : StringBuilder, values : Array[String]) -> Unit {
  for i = 0; i < values.length(); i = i + 1 {
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string(json_string(values[i]))
  }
}

// A JSON string literal (UTF-8 passthrough, escaping quote, backslash and
// control characters).
fn json_string(s : String) -> String {
  let sb = StringBuilder()
  sb.write_string("\"")
  for ch in s {
    let v = ch.to_int()
    if ch == '"' {
      sb.write_string("\\\"")
    } else if ch == '\\' {
      sb.write_string("\\\\")
    } else if v == 0x08 {
      sb.write_string("\\b")
    } else if v == 0x0C {
      sb.write_string("\\f")
    } else if v == 0x0A {
      sb.write_string("\\n")
    } else if v == 0x0D {
      sb.write_string("\\r")
    } else if v == 0x09 {
      sb.write_string("\\t")
    } else if v < 0x20 {
      // Four lowercase hex digits: control characters only (v < 0x20), so
      // the two high nibbles are always "00".
      sb.write_string("\\u00")
      sb.write_char(hex_nibble(v >> 4))
      sb.write_char(hex_nibble(v & 0xF))
    } else {
      sb.write_char(ch)
    }
  }
  sb.write_string("\"")
  sb.to_string()
}

fn json_bool(b : Bool) -> String {
  if b {
    "true"
  } else {
    "false"
  }
}

// A single lowercase hex digit character (0-9 a-f) for a nibble 0-15.
fn hex_nibble(n : Int) -> Char {
  if n < 10 {
    ('0'.to_int() + n).to_char().unwrap()
  } else {
    ('a'.to_int() + n - 10).to_char().unwrap()
  }
}

// A stable programmatic name for a FilenameSource, shared with the tests.
fn filename_source_name(src : FilenameSource) -> String {
  match src {
    Filename => "filename"
    FilenameStar => "filename*"
  }
}
