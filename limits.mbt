// limits.mbt — Resource limits for moon-content-disposition.
//
// Content-Disposition header values are external, untrusted input. A
// hostile or buggy sender can produce multi-megabyte headers, hundreds of
// parameters, or extremely long values. Every public parser accepts a
// `Limits` value that bounds how much work a single parse may do. When a
// limit is exceeded the parser returns
// `DispositionErrorKind::LimitExceeded`; it never panics, never loops
// forever, and never silently truncates.
//
// Three presets are provided:
//   - `default()`    — generous, safe for normal use.
//   - `strict()`     — tight, for constrained deployments where every byte
//     counts.
//   - `permissive()` — large, for batch processing of known-good input.

///|
/// Bounds applied while parsing or generating Content-Disposition data.
pub struct Limits {
  max_input_bytes : Int
  max_parameters : Int
  max_parameter_name_bytes : Int
  max_parameter_value_bytes : Int
  max_filename_bytes : Int
  max_extended_value_bytes : Int
  max_context_bytes : Int
}

///|
/// Default limits. Intended for interactive and typical server use.
pub fn Limits::default() -> Limits {
  {
    max_input_bytes: 1 << 20,
    max_parameters: 256,
    max_parameter_name_bytes: 256,
    max_parameter_value_bytes: 8192,
    max_filename_bytes: 1024,
    max_extended_value_bytes: 8192,
    max_context_bytes: 80,
  }
}

///|
/// Strict limits. Intended for constrained deployments that expect small,
/// well-formed headers.
pub fn Limits::strict() -> Limits {
  {
    max_input_bytes: 16 * 1024,
    max_parameters: 32,
    max_parameter_name_bytes: 64,
    max_parameter_value_bytes: 1024,
    max_filename_bytes: 255,
    max_extended_value_bytes: 1024,
    max_context_bytes: 80,
  }
}

///|
/// Permissive limits. Intended for batch processing of trusted data with
/// very large headers.
pub fn Limits::permissive() -> Limits {
  {
    max_input_bytes: 64 << 20,
    max_parameters: 4096,
    max_parameter_name_bytes: 1024,
    max_parameter_value_bytes: 4 << 20,
    max_filename_bytes: 8192,
    max_extended_value_bytes: 4 << 20,
    max_context_bytes: 160,
  }
}

///|
/// The input byte bound.
pub fn Limits::max_input_bytes(self : Limits) -> Int {
  self.max_input_bytes
}

///|
/// The parameter count bound.
pub fn Limits::max_parameters(self : Limits) -> Int {
  self.max_parameters
}

///|
/// The parameter name byte bound.
pub fn Limits::max_parameter_name_bytes(self : Limits) -> Int {
  self.max_parameter_name_bytes
}

///|
/// The plain parameter value byte bound.
pub fn Limits::max_parameter_value_bytes(self : Limits) -> Int {
  self.max_parameter_value_bytes
}

///|
/// The filename byte bound, used by the resolver, the policy and the
/// generator.
pub fn Limits::max_filename_bytes(self : Limits) -> Int {
  self.max_filename_bytes
}

///|
/// The RFC 8187 extended value byte bound.
pub fn Limits::max_extended_value_bytes(self : Limits) -> Int {
  self.max_extended_value_bytes
}

///|
/// The error context excerpt bound.
pub fn Limits::max_context_bytes(self : Limits) -> Int {
  self.max_context_bytes
}

///|
/// The context excerpt bound used when building error messages. This is a
/// module-level convenience returning the `default()` limit so that
/// callers that construct errors directly do not need to thread a `Limits`
/// value.
pub fn max_context_bytes() -> Int {
  80
}
