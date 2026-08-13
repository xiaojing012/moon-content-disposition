// wasm-gc exit-code support for `disposition-tool`.

///|
/// Terminates the process with the given exit code.
#cfg(target="wasm-gc")
fn cli_process_exit(code : Int) -> Unit = "__moonbit_sys_unstable" "exit"

///|
#cfg(target="wasm-gc")
fn cli_exit(code : Int) -> Unit {
  cli_process_exit(code)
}
