// examples/parse/main.mbt — Parses an RFC 6266 Content-Disposition header
// field value and prints the resulting model.
//
//   moon run examples/parse
//   moon run examples/parse -- "attachment; filename=\"report.pdf\"; size=1024"

fn main {
  let value = input_or_default("attachment; filename=\"report.pdf\"; size=1024")
  println("value:      \{value}")
  match @cd.parse_content_disposition(value) {
    Err(e) => println("parse error: \{e.to_display()}")
    Ok(cd) => {
      println("type:       \{cd.disposition_type().to_lower_name()}")
      println("parameters: \{cd.parameter_count()}")
      for p in cd.parameters() {
        println("  \{p.name()} = \{render_value(p.value())}")
      }
    }
  }
}

fn render_value(v : @cd.ParameterValue) -> String {
  match v.extended() {
    Some(ev) => "extended \{ev.charset()}\{render_lang(ev.language())}'\{ev.value()}"
    None => "plain \"\{v.plain().unwrap()}\""
  }
}

fn render_lang(lang : String?) -> String {
  match lang {
    Some(t) => t
    None => ""
  }
}

// Reads the user-supplied value from the command line. The argv shape
// differs per backend:
//
//   native / wasm-gc: [program, value...]
//   js:               [node, program.js, value...]
//
// The program (and, on js, the runtime binary and script path) is skipped; a
// single header value may span several argv elements, so the remainder is
// joined with a single space. With no user argument the given fallback is
// used.
fn input_or_default(fallback : String) -> String {
  let args = @env.args()
  let mut start = 1
  if args.length() >= 3 && is_runtime_binary(args[0]) && is_script_path(args[1]) {
    start = 2
  }
  if args.length() <= start {
    return fallback
  }
  if is_script_path(args[start]) {
    return fallback
  }
  let sb = StringBuilder()
  for i = start; i < args.length(); i = i + 1 {
    if i > start {
      sb.write_string(" ")
    }
    sb.write_string(args[i])
  }
  sb.to_string()
}

// Whether a leading argument is a runtime binary (the node executable that
// precedes the script path on the js backend).
fn is_runtime_binary(arg : String) -> Bool {
  let lower = arg.to_lower()
  lower == "node" || lower == "deno" || lower == "bun" || lower.has_suffix("node.exe")
}

// Whether an argument is a program script path (a path ending in a script
// extension).
fn is_script_path(arg : String) -> Bool {
  if !(arg.contains("/") || arg.contains("\\")) {
    return false
  }
  let lower = arg.to_lower()
  lower.has_suffix(".js") || lower.has_suffix(".cjs") || lower.has_suffix(".mjs")
}
