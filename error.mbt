// error.mbt — Structured error model for moon-content-disposition.
//
// Content-Disposition processing has many distinct failure modes across
// several processing stages. Public APIs never return `Result[T, String]`;
// they return `Result[T, DispositionError]` so callers can dispatch on a
// stable (stage, kind) pair, an optional UTF-8 byte offset, and a short
// context string.
//
// `DispositionError` is declared as a `suberror` (MoonBit's raise-based
// error type). Internal processing functions use `raise DispositionError`
// and let errors propagate through the call stack without plumbing; every
// public boundary function wraps those internals in `try`/`catch` and
// converts to `Result[T, DispositionError]`.
//
// Offsets are UTF-8 byte offsets into the exact input string that was
// passed to the public entry point. The offset is `0` when it is not
// meaningful for the kind of error (for example limit checks that do not
// map to a single byte). The `context` string is a short, truncated excerpt
// of the input around the failure point; it never echoes the whole
// (possibly megabytes-long) header.

///|
/// The processing stage in which an error was detected.
pub enum DispositionErrorStage {
  Input
  DispositionType
  ParameterName
  ParameterValue
  Token
  QuotedString
  ExtendedValue
  PercentEncoding
  Charset
  FilenameResolution
  FilenamePolicy
  Serialization
  Limit
}

///|
/// The concrete error category. Stable across versions so callers can
/// switch on it without string matching.
pub enum DispositionErrorKind {
  EmptyInput
  InvalidDispositionType
  ExpectedToken
  UnexpectedCharacter
  MissingEquals
  MissingParameterValue
  InvalidParameterName
  DuplicateParameter
  UnterminatedQuotedString
  InvalidQuotedPair
  InvalidControlCharacter
  InvalidExtendedValue
  MissingCharset
  InvalidCharset
  UnsupportedCharset
  InvalidLanguage
  InvalidPercentEncoding
  InvalidUtf8
  InvalidFilename
  UnsafeFilename
  LimitExceeded
  TrailingInput
}

///|
/// A structured error returned by every public API.
///
/// - `stage()` — where the failure happened.
/// - `kind()` — what failed.
/// - `offset()` — UTF-8 byte offset into the input, `0` when not meaningful.
/// - `context()` — short excerpt of the input at the failure point
///   (bounded, never the full input).
pub suberror DispositionError {
  DispositionError(DispositionErrorStage, DispositionErrorKind, Int, String)
}

///|
/// Constructs a `DispositionError` with the given stage, kind and context
/// and a zero offset.
pub fn disposition_error(
  stage : DispositionErrorStage,
  kind : DispositionErrorKind,
  context : String
) -> DispositionError {
  DispositionError(stage, kind, 0, context)
}

///|
/// Constructs a `DispositionError` carrying an explicit UTF-8 byte offset.
pub fn disposition_error_at(
  stage : DispositionErrorStage,
  kind : DispositionErrorKind,
  offset : Int,
  context : String
) -> DispositionError {
  DispositionError(stage, kind, offset, context)
}

///|
/// The stage in which this error was detected.
pub fn DispositionError::stage(self : DispositionError) -> DispositionErrorStage {
  match self {
    DispositionError(stage, _, _, _) => stage
  }
}

///|
/// The concrete kind of this error.
pub fn DispositionError::kind(self : DispositionError) -> DispositionErrorKind {
  match self {
    DispositionError(_, kind, _, _) => kind
  }
}

///|
/// The UTF-8 byte offset into the input where the error was detected, or
/// `0` when the offset is not meaningful for this error kind.
pub fn DispositionError::offset(self : DispositionError) -> Int {
  match self {
    DispositionError(_, _, offset, _) => offset
  }
}

///|
/// A short, bounded excerpt of the input around the failure point.
pub fn DispositionError::context(self : DispositionError) -> String {
  match self {
    DispositionError(_, _, _, context) => context
  }
}

///|
/// A single-line human readable rendering of the error, intended for
/// terminal output and CLI use.
pub fn DispositionError::to_display(self : DispositionError) -> String {
  let DispositionError(stage, kind, offset, context) = self
  "\{stage.to_string()}::\{kind.to_string()} at byte \{offset}: \{context}"
}

///|
/// Stable programmatic name for a stage, used by the CLI JSON output.
pub fn DispositionErrorStage::to_string(self : DispositionErrorStage) -> String {
  match self {
    Input => "Input"
    DispositionType => "DispositionType"
    ParameterName => "ParameterName"
    ParameterValue => "ParameterValue"
    Token => "Token"
    QuotedString => "QuotedString"
    ExtendedValue => "ExtendedValue"
    PercentEncoding => "PercentEncoding"
    Charset => "Charset"
    FilenameResolution => "FilenameResolution"
    FilenamePolicy => "FilenamePolicy"
    Serialization => "Serialization"
    Limit => "Limit"
  }
}

///|
/// Stable programmatic name for a kind, used by the CLI JSON output.
pub fn DispositionErrorKind::to_string(self : DispositionErrorKind) -> String {
  match self {
    EmptyInput => "EmptyInput"
    InvalidDispositionType => "InvalidDispositionType"
    ExpectedToken => "ExpectedToken"
    UnexpectedCharacter => "UnexpectedCharacter"
    MissingEquals => "MissingEquals"
    MissingParameterValue => "MissingParameterValue"
    InvalidParameterName => "InvalidParameterName"
    DuplicateParameter => "DuplicateParameter"
    UnterminatedQuotedString => "UnterminatedQuotedString"
    InvalidQuotedPair => "InvalidQuotedPair"
    InvalidControlCharacter => "InvalidControlCharacter"
    InvalidExtendedValue => "InvalidExtendedValue"
    MissingCharset => "MissingCharset"
    InvalidCharset => "InvalidCharset"
    UnsupportedCharset => "UnsupportedCharset"
    InvalidLanguage => "InvalidLanguage"
    InvalidPercentEncoding => "InvalidPercentEncoding"
    InvalidUtf8 => "InvalidUtf8"
    InvalidFilename => "InvalidFilename"
    UnsafeFilename => "UnsafeFilename"
    LimitExceeded => "LimitExceeded"
    TrailingInput => "TrailingInput"
  }
}

///|
/// Unwraps a `Result` inside a `raise` function, re-raising the structured
/// error. This is the MoonBit 0.1.2026 equivalent of the `?` operator: the
/// public boundary functions below use it to convert the internal
/// raise-based error flow into `Result[T, DispositionError]`.
fn[T] unwrap_or_raise(r : Result[T, DispositionError]) -> T raise {
  match r {
    Ok(v) => v
    Err(e) => raise e
  }
}

///|
/// Downcasts the abstract `Error` caught in a `catch` clause back to the
/// concrete `DispositionError`. Every function in this package raises
/// `DispositionError` exclusively, so any other suberror reaching this
/// boundary is a bug and is reported loudly rather than silently lost.
fn unwrap_disposition_error(e : Error) -> DispositionError {
  match e {
    DispositionError(stage, kind, offset, context) =>
      DispositionError(stage, kind, offset, context)
    _ => abort("internal error: unexpected non-DispositionError propagated to a Result boundary")
  }
}
