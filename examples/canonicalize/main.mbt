// examples/canonicalize/main.mbt — Canonicalises a Content-Disposition
// value (lowercased type and names, filename before filename*, deterministic
// encoding) and shows that the operation is idempotent.
//
//   moon run examples/canonicalize
//   moon run examples/canonicalize -- "ATTACHMENT; FILENAME*=UTF-8'en'caf%C3%A9.pdf; FILENAME=fallback.txt; SIZE=42"

fn main {
  let value = input_or_default(
    "ATTACHMENT; FILENAME*=UTF-8'en'caf%C3%A9.pdf; FILENAME=fallback.txt; SIZE=42",
  )
  println("input:         \{value}")
  match @cd.canonicalize_content_disposition(value) {
    Err(e) => println("canonicalize error: \{e.to_display()}")
    Ok(c1) => {
      println("canonical:     \{c1}")
      match @cd.canonicalize_content_disposition(c1) {
        Err(e) => println("second pass error: \{e.to_display()}")
        Ok(c2) => {
          println("canonicalised: \{c2}")
          println("idempotent:    \{if c1 == c2 { "yes" } else { "no" }}")
        }
      }
    }
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
