///|
/// `disposition-tool` — the RFC 6266 Content-Disposition command-line
/// toolkit. Every command emits a single JSON object on stdout; a failed
/// command exits with status 1.
///
/// Usage:
///   disposition-tool parse <value>
///   disposition-tool serialize <value>
///   disposition-tool canonicalize <value>
///   disposition-tool resolve <value>
///   disposition-tool sanitize <name> [portable|windows-like|posix-like]
///   disposition-tool generate <attachment|inline> <name>
///   disposition-tool audit <value>
///   disposition-tool limits [default|strict|permissive]
///   disposition-tool profiles
///   disposition-tool version
///   disposition-tool help
fn main {
  let args = @env.args()
  let rest = strip_program_name(args)
  let out = @cd.run_cli(rest)
  println(out)
  if out.has_prefix("{\"ok\":false") {
    cli_exit(1)
  }
}

// Drops leading program/runtime paths from the argument list. The argv shape
// differs per backend:
//
//   native / wasm-gc: [program, args...]
//   js:               [node, program.js, args...]
//
// Program paths are recognised by shape (a path ending in a program
// extension, or a known runtime binary name) and dropped until the first
// known command or the user's first argument is reached, so the backend
// never leaks into `run_cli`.
fn strip_program_name(args : Array[String]) -> Array[String] {
  let known = [
    "parse", "serialize", "canonicalize", "resolve", "sanitize", "generate",
    "audit", "limits", "profiles", "version", "help",
  ]
  let mut i = 0
  while i < args.length() {
    let a = args[i]
    let mut is_command = false
    for k in known {
      if a == k || a == k.to_upper() {
        is_command = true
      }
    }
    if is_command {
      break
    }
    if !is_program_path(a) {
      break
    }
    i = i + 1
  }
  args[i:].to_owned()
}

// Whether a leading argument is the running program (or its runtime binary)
// rather than a user-supplied command. Program paths carry a directory
// separator and a known program extension; runtime binaries are recognised by
// their bare names.
fn is_program_path(arg : String) -> Bool {
  let lower = arg.to_lower()
  if lower == "node" || lower == "deno" || lower == "bun" {
    return true
  }
  if !(arg.contains("/") || arg.contains("\\")) {
    return false
  }
  lower.has_suffix(".exe") || lower.has_suffix(".js") || lower.has_suffix(".cjs") ||
    lower.has_suffix(".mjs") || lower.has_suffix(".wasm")
}
