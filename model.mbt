// model.mbt — Core data model for moon-content-disposition.
//
// The model follows the abstract model of RFC 6266 Section 4: a
// Content-Disposition header field value is a disposition type followed by
// zero or more disposition parameters. The model keeps every parsed
// parameter (including extension parameters and duplicates) in input order
// so that no information is lost between parsing and serialising. Typed
// convenience accessors (`filename()`, `filename_star()`,
// `preferred_filename()`) are layered on top of the ordered raw model rather
// than replacing it.
//
// Design notes:
//   - Parameter names are compared case-insensitively (RFC 6266
//     Section 4.2) but stored exactly as parsed so that serialising a
//     parsed header preserves the original casing until canonicalisation.
//   - `ParameterValue::Token` and `ParameterValue::Quoted` are kept
//     distinct: the RFC 6266 `value` rule is `token / quoted-string`, and
//     keeping the two forms apart lets the serializer emit the same wire
//     form it received (deterministic round-tripping).
//   - `ParameterValue::Extended` carries the RFC 8187 extended value used
//     by `filename*` and any extension parameter whose name ends with `*`.
//   - `ContentDisposition` is a value type: it never mutates in place.

///|
/// The disposition type of a Content-Disposition field value.
///
/// `Inline` and `Attachment` are the two registered disposition types
/// (RFC 6266 Section 4.1); anything else is a valid extension token
/// (`disp-ext-type`), preserved verbatim.
pub enum DispositionType {
  Inline
  Attachment
  Extension(String)
}

///|
/// The value of a single disposition parameter.
///
/// `Token` is the unquoted `token` form, `Quoted` is the `quoted-string`
/// form, and `Extended` is an RFC 8187 extended value (used when the
/// parameter name ends with `*`).
pub enum ParameterValue {
  Token(String)
  Quoted(String)
  Extended(ExtendedValue)
}

///|
/// An RFC 8187 extended value: a charset name, an optional language tag,
/// and the decoded value. The charset is always a supported charset
/// (`UTF-8` or `ISO-8859-1`, stored in canonical casing) after validation;
/// the value is the fully decoded string.
pub struct ExtendedValue {
  charset : String
  language : String?
  value : String
}

///|
/// A single disposition parameter: a name and a value.
pub struct DispositionParameter {
  name : String
  value : ParameterValue
}

///|
/// A parsed Content-Disposition header field value.
///
/// `parameters` preserves the input order of every parameter, including
/// extension parameters and (in compatible mode) duplicates. The typed
/// accessors below look parameters up without consuming them.
pub struct ContentDisposition {
  disposition_type : DispositionType
  parameters : Array[DispositionParameter]
  raw_disposition_type : String?
}

///|
/// The single library version string, used by `moon --version`-style
/// reporting, the CLI and the module metadata. Kept in one place so the
/// final maintainer can update it (together with `moon.mod`) in one step.
pub fn library_version() -> String {
  "0.1.0-dev"
}

///|
/// Constructs an `ExtendedValue` from its parts.
pub fn extended_value(
  charset : String,
  language : String?,
  value : String
) -> ExtendedValue {
  { charset, language, value }
}

///|
/// Constructs a `DispositionParameter` from its parts.
pub fn disposition_parameter(name : String, value : ParameterValue) -> DispositionParameter {
  { name, value }
}

///|
/// Constructs a `ContentDisposition` with the given disposition type and
/// no parameters. Hand-built values have no raw disposition type; the
/// preserve-case serializer falls back to the canonical spelling.
pub fn content_disposition(disposition_type : DispositionType) -> ContentDisposition {
  { disposition_type, parameters: Array::new(), raw_disposition_type: None }
}

///|
/// Constructs a `ContentDisposition` while remembering the exact disposition
/// type token as it appeared on the wire, so that a preserve-case
/// serialisation can emit it verbatim. Used by the parser.
pub fn content_disposition_with_raw(
  disposition_type : DispositionType,
  raw : String
) -> ContentDisposition {
  { disposition_type, parameters: Array::new(), raw_disposition_type: Some(raw) }
}

///|
/// The disposition type.
pub fn ContentDisposition::disposition_type(self : ContentDisposition) -> DispositionType {
  self.disposition_type
}

///|
/// The disposition type token exactly as it appeared in the input, if this
/// value was produced by parsing (never present on hand-built models).
pub fn ContentDisposition::raw_disposition_type(self : ContentDisposition) -> String? {
  self.raw_disposition_type
}

///|
/// All parameters, in input order.
pub fn ContentDisposition::parameters(self : ContentDisposition) -> Array[DispositionParameter] {
  self.parameters
}

///|
/// The number of parameters.
pub fn ContentDisposition::parameter_count(self : ContentDisposition) -> Int {
  self.parameters.length()
}

///|
/// The parameter with the given name (case-insensitive), or `None`. If the
/// name appears more than once, the first occurrence is returned.
pub fn ContentDisposition::get_parameter(
  self : ContentDisposition,
  name : String
) -> DispositionParameter? {
  for p in self.parameters {
    if p.name.equal_ignore_ascii_case(name) {
      return Some(p)
    }
  }
  None
}

///|
/// The disposition type token, lower-cased for comparison.
pub fn DispositionType::to_lower_name(self : DispositionType) -> String {
  match self {
    Inline => "inline"
    Attachment => "attachment"
    Extension(name) => name.to_lower()
  }
}

///|
/// Whether the disposition type is the registered `inline` type.
pub fn DispositionType::is_inline(self : DispositionType) -> Bool {
  match self {
    Inline => true
    _ => false
  }
}

///|
/// Whether the disposition type is the registered `attachment` type.
pub fn DispositionType::is_attachment(self : DispositionType) -> Bool {
  match self {
    Attachment => true
    _ => false
  }
}

///|
/// Whether the disposition type is an extension token.
pub fn DispositionType::is_extension(self : DispositionType) -> Bool {
  match self {
    Extension(_) => true
    _ => false
  }
}

///|
/// The extension token, if this is an extension disposition type.
pub fn DispositionType::extension_name(self : DispositionType) -> String? {
  match self {
    Extension(name) => Some(name)
    _ => None
  }
}

///|
/// The parameter name.
pub fn DispositionParameter::name(self : DispositionParameter) -> String {
  self.name
}

///|
/// The parameter value.
pub fn DispositionParameter::value(self : DispositionParameter) -> ParameterValue {
  self.value
}

///|
/// Whether the parameter name ends with `*` (the RFC 8187 extended form).
pub fn DispositionParameter::is_extended(self : DispositionParameter) -> Bool {
  self.name.has_suffix("*")
}

///|
/// The plain string content of a non-extended parameter value, if this
/// value is not the extended form.
pub fn ParameterValue::plain(self : ParameterValue) -> String? {
  match self {
    Token(s) => Some(s)
    Quoted(s) => Some(s)
    Extended(_) => None
  }
}

///|
/// The extended value, if this is the extended form.
pub fn ParameterValue::extended(self : ParameterValue) -> ExtendedValue? {
  match self {
    Extended(ev) => Some(ev)
    _ => None
  }
}

///|
/// Whether this value is the RFC 8187 extended form.
pub fn ParameterValue::is_extended(self : ParameterValue) -> Bool {
  match self {
    Extended(_) => true
    _ => false
  }
}

///|
/// The charset of this extended value.
pub fn ExtendedValue::charset(self : ExtendedValue) -> String {
  self.charset
}

///|
/// The optional language tag of this extended value.
pub fn ExtendedValue::language(self : ExtendedValue) -> String? {
  self.language
}

///|
/// The decoded value of this extended value.
pub fn ExtendedValue::value(self : ExtendedValue) -> String {
  self.value
}

///|
/// The value of the last `filename` parameter, if present. Only the plain
/// (non-extended) `filename` parameter is considered; the decoded value of
/// `filename*` is exposed through `filename_star()`.
pub fn ContentDisposition::filename(self : ContentDisposition) -> String? {
  let mut result : String? = None
  for p in self.parameters {
    if p.name.equal_ignore_ascii_case("filename") {
      match p.value.plain() {
        Some(v) => result = Some(v)
        None => ()
      }
    }
  }
  result
}

///|
/// The decoded extended value of the last `filename*` parameter, if present.
pub fn ContentDisposition::filename_star(self : ContentDisposition) -> ExtendedValue? {
  let mut result : ExtendedValue? = None
  for p in self.parameters {
    if p.name.equal_ignore_ascii_case("filename*") {
      match p.value {
        Extended(ev) => result = Some(ev)
        _ => ()
      }
    }
  }
  result
}

///|
/// Whether this disposition type matches the given token, case-insensitively.
pub fn DispositionType::matches(self : DispositionType, name : String) -> Bool {
  match self {
    Inline => name.equal_ignore_ascii_case("inline")
    Attachment => name.equal_ignore_ascii_case("attachment")
    Extension(n) => n.equal_ignore_ascii_case(name)
  }
}

///|
/// Semantic equality between two extended values: charset, language and
/// value. Used by round-trip tests.
pub fn ExtendedValue::semantic_equal(self : ExtendedValue, other : ExtendedValue) -> Bool {
  self.charset.equal_ignore_ascii_case(other.charset) &&
    self.language == other.language && self.value == other.value
}

///|
/// Semantic equality between two parameter values. Token and Quoted forms
/// of the same string are considered different forms but semantically equal
/// content; extended values are compared structurally.
pub fn ParameterValue::semantic_equal(self : ParameterValue, other : ParameterValue) -> Bool {
  match (self, other) {
    (Token(a), Token(b)) => a == b
    (Quoted(a), Quoted(b)) => a == b
    (Token(a), Quoted(b)) => a == b
    (Quoted(a), Token(b)) => a == b
    (Extended(a), Extended(b)) => a.semantic_equal(b)
    _ => false
  }
}

///|
/// Semantic equality between two parameters: names are compared
/// case-insensitively, values structurally.
pub fn DispositionParameter::semantic_equal(
  self : DispositionParameter,
  other : DispositionParameter
) -> Bool {
  self.name.equal_ignore_ascii_case(other.name) && self.value.semantic_equal(other.value)
}

///|
/// Semantic equality between two Content-Disposition values. Parameter
/// order must match; names are compared case-insensitively.
pub fn ContentDisposition::semantic_equal(
  self : ContentDisposition,
  other : ContentDisposition
) -> Bool {
  if !self.disposition_type.to_lower_name().equal_ignore_ascii_case(
    other.disposition_type.to_lower_name(),
  ) {
    return false
  }
  if self.parameters.length() != other.parameters.length() {
    return false
  }
  for i = 0; i < self.parameters.length(); i = i + 1 {
    if !self.parameters[i].semantic_equal(other.parameters[i]) {
      return false
    }
  }
  true
}

///|
/// A compact human-readable rendering used by tests and the CLI.
pub fn ContentDisposition::to_debug_string(self : ContentDisposition) -> String {
  let sb = StringBuilder()
  sb.write_string(self.disposition_type.to_lower_name())
  for p in self.parameters {
    sb.write_string("; ")
    sb.write_string(p.name)
    sb.write_string("=")
    match p.value {
      Token(v) => sb.write_string(v)
      Quoted(v) => sb.write_string(serialize_quoted_string(v))
      Extended(ev) => {
        sb.write_string(ev.charset)
        sb.write_string("'")
        match ev.language {
          Some(l) => sb.write_string(l)
          None => ()
        }
        sb.write_string("'")
        sb.write_string(ev.value)
      }
    }
  }
  sb.to_string()
}
