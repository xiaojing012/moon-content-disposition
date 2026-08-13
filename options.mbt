// options.mbt — Parse options for moon-content-disposition.
//
// RFC 6266 and RFC 8187 leave a number of edge cases to the
// implementation. `ParseOptions` bundles the two axes that every caller
// should be able to control independently: the parse mode (strict vs
// compatible) and the resource limits. Keeping the two separate lets a
// caller run a strict parser with generous limits, or a compatible parser
// with tight limits, without inventing extra option objects.

///|
/// The parse mode.
///
/// `Strict` follows the project-defined RFC 6266 / RFC 8187 scope without
/// leniency. `Compatible` additionally accepts a small, individually
/// documented set of real-world behaviours; every compatible recovery is
/// recorded in the parse result and in the audit report so that no
/// deviation is silent. Compatible mode never relaxes security-critical
/// validation (control-character rejection, percent-encoding validation,
/// charset validation).
pub enum ParseMode {
  Strict
  Compatible
} derive(Eq)

///|
/// Options controlling one parse (or canonicalisation) operation.
pub struct ParseOptions {
  mode : ParseMode
  limits : Limits
}

///|
/// Constructs default parse options: `Strict` mode with `Limits::default()`.
pub fn ParseOptions::new() -> ParseOptions {
  { mode: Strict, limits: Limits::default() }
}

///|
/// Default parse options: `Strict` mode with `Limits::default()`.
pub fn ParseOptions::default() -> ParseOptions {
  { mode: Strict, limits: Limits::default() }
}

///|
/// `Compatible` mode with `Limits::default()`.
pub fn ParseOptions::compatible() -> ParseOptions {
  { mode: Compatible, limits: Limits::default() }
}

///|
/// `Strict` mode with `Limits::strict()`.
pub fn ParseOptions::strict() -> ParseOptions {
  { mode: Strict, limits: Limits::strict() }
}

///|
/// `Strict` mode with `Limits::permissive()`.
pub fn ParseOptions::permissive() -> ParseOptions {
  { mode: Strict, limits: Limits::permissive() }
}

///|
/// The parse mode of these options.
pub fn ParseOptions::mode(self : ParseOptions) -> ParseMode {
  self.mode
}

///|
/// The limits of these options.
pub fn ParseOptions::limits(self : ParseOptions) -> Limits {
  self.limits
}

///|
/// A copy of these options with the given mode.
pub fn ParseOptions::with_mode(self : ParseOptions, mode : ParseMode) -> ParseOptions {
  { mode, limits: self.limits }
}

///|
/// A copy of these options with the given limits.
pub fn ParseOptions::with_limits(self : ParseOptions, limits : Limits) -> ParseOptions {
  { mode: self.mode, limits }
}

///|
/// A stable programmatic name for a parse mode.
pub fn ParseMode::to_string(self : ParseMode) -> String {
  match self {
    Strict => "strict"
    Compatible => "compatible"
  }
}
