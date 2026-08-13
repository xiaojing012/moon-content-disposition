// Native exit-code support for `disposition-tool`.

///|
/// Terminates the process with the given exit code.
#cfg(target="native")
extern "c" fn cli_process_exit(code : Int) = "exit"

///|
#cfg(target="native")
fn cli_exit(code : Int) -> Unit {
  cli_process_exit(code)
}
