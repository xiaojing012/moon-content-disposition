// JS exit-code support for `disposition-tool`.

///|
/// Terminates the process with the given exit code.
#cfg(target="js")
extern "js" fn cli_process_exit(code : Int) =
  #| function(code) {
  #|   if (typeof process !== "undefined" && typeof process.exit === "function") {
  #|     process.exit(code);
  #|   }
  #| }

///|
#cfg(target="js")
fn cli_exit(code : Int) -> Unit {
  cli_process_exit(code)
}
