// audit.mbt — Advisory security audit of a Content-Disposition value.
//
// Parsing answers "what does this header say?"; auditing answers "is there
// anything here that a careful HTTP client should look at twice?". The audit
// functions below inspect a parsed `ContentDisposition` (or a raw filename)
// and produce a list of `AuditIssue`s covering the well-known RFC 6266
// Section 7 concerns: ambiguous filenames, path separators, control
// characters, non-ASCII values without an RFC 8187 companion, duplicated
// parameters, risky file extensions and Windows reserved names.
//
// Auditing is advisory: an audit report never changes the parsed value and
// never raises. Every issue carries a severity so callers can implement a
// policy ("reject High issues", "log Warnings", ...).

///|
/// The severity of an audit issue. `Info` is informational, `Warning`
/// deserves attention, `High` should normally cause the download to be
/// treated as risky.
pub enum AuditSeverity {
  Info
  Warning
  High
}

///|
/// The stable category of an audit issue.
pub enum AuditKind {
  /// Neither `filename` nor `filename*` is present.
  MissingFilename
  /// The chosen filename is the empty string.
  EmptyFilename
  /// Both `filename` and `filename*` are present.
  BothFilenameAndFilenameStar
  /// Only the plain `filename` parameter is present (no RFC 8187 companion).
  PlainFilenameOnly
  /// `filename*` is present without a plain `filename` fallback.
  FilenameStarWithoutFallback
  /// The filename contains a `/` or `\` path separator.
  PathSeparatorInFilename
  /// The filename contains a control character (including CR/LF/NUL).
  ControlCharacterInFilename
  /// The plain `filename` contains non-ASCII bytes (legacy, unquoted form).
  NonAsciiUnquotedFilename
  /// A non-ASCII filename is not accompanied by an RFC 8187 `filename*`.
  MissingFilenameStarForNonAscii
  /// An extended value used an unsupported charset.
  UnsupportedCharset
  /// An extended value carried an invalid RFC 5646 language tag.
  InvalidLanguageTag
  /// A parameter name appeared more than once.
  DuplicateParameter
  /// A compatible-mode recovery was applied during parsing.
  RecoveryApplied
  /// The filename extension is in the executable/script risk list.
  ExtensionRisk
  /// The filename is a Windows reserved device name (CON, PRN, ...).
  ReservedWindowsName
  /// The filename ends in a dot or a space (silently trimmed by Windows).
  TrailingDotOrSpace
  /// The filename is long enough to be truncated by common file systems.
  LongFilename
  /// The disposition type is an extension type, not `inline`/`attachment`.
  ExtensionDispositionType
}

///|
/// A single audit finding.
pub struct AuditIssue {
  severity : AuditSeverity
  kind : AuditKind
  parameter : String
  message : String
}

///|
/// The severity of this issue.
pub fn AuditIssue::severity(self : AuditIssue) -> AuditSeverity {
  self.severity
}

///|
/// The stable kind of this issue.
pub fn AuditIssue::kind(self : AuditIssue) -> AuditKind {
  self.kind
}

///|
/// The parameter the issue concerns (`filename`, `filename*`, or an empty
/// string for issues that concern the whole value).
pub fn AuditIssue::parameter(self : AuditIssue) -> String {
  self.parameter
}

///|
/// A human-readable explanation of the issue.
pub fn AuditIssue::message(self : AuditIssue) -> String {
  self.message
}

///|
/// The result of an audit: the issues found, in a stable order.
pub struct AuditReport {
  issues : Array[AuditIssue]
}

///|
/// An empty audit report.
pub fn AuditReport::empty() -> AuditReport {
  { issues: [] }
}

///|
/// The issues found, in a stable order.
pub fn AuditReport::issues(self : AuditReport) -> Array[AuditIssue] {
  self.issues
}

///|
/// The number of issues.
pub fn AuditReport::issue_count(self : AuditReport) -> Int {
  self.issues.length()
}

///|
/// The number of issues at or above the given severity. Severity values are
/// obtained from `AuditIssue::severity()` (enum variants cannot be named in
/// expression position from consumer packages); `count_high` and
/// `count_at_least_warning` are the convenient forms.
pub fn AuditReport::count_severity(self : AuditReport, severity : AuditSeverity) -> Int {
  let mut n = 0
  for i in self.issues {
    if severity_rank(i.severity()) >= severity_rank(severity) {
      n = n + 1
    }
  }
  n
}

///|
/// The number of High-severity issues.
pub fn AuditReport::count_high(self : AuditReport) -> Int {
  self.count_severity_of_rank(2)
}

///|
/// The number of issues at Warning severity or above.
pub fn AuditReport::count_at_least_warning(self : AuditReport) -> Int {
  self.count_severity_of_rank(1)
}

// Counts issues whose severity rank is at least `rank`.
fn AuditReport::count_severity_of_rank(self : AuditReport, rank : Int) -> Int {
  let mut n = 0
  for i in self.issues {
    if severity_rank(i.severity()) >= rank {
      n = n + 1
    }
  }
  n
}

///|
/// A stable programmatic name for a severity.
pub fn AuditSeverity::to_string(self : AuditSeverity) -> String {
  match self {
    Info => "info"
    Warning => "warning"
    High => "high"
  }
}

///|
/// A stable programmatic name for a kind, used by the CLI JSON output.
pub fn AuditKind::to_string(self : AuditKind) -> String {
  match self {
    MissingFilename => "missing-filename"
    EmptyFilename => "empty-filename"
    BothFilenameAndFilenameStar => "both-filename-and-filename-star"
    PlainFilenameOnly => "plain-filename-only"
    FilenameStarWithoutFallback => "filename-star-without-fallback"
    PathSeparatorInFilename => "path-separator-in-filename"
    ControlCharacterInFilename => "control-character-in-filename"
    NonAsciiUnquotedFilename => "non-ascii-unquoted-filename"
    MissingFilenameStarForNonAscii => "missing-filename-star-for-non-ascii"
    UnsupportedCharset => "unsupported-charset"
    InvalidLanguageTag => "invalid-language-tag"
    DuplicateParameter => "duplicate-parameter"
    RecoveryApplied => "recovery-applied"
    ExtensionRisk => "extension-risk"
    ReservedWindowsName => "reserved-windows-name"
    TrailingDotOrSpace => "trailing-dot-or-space"
    LongFilename => "long-filename"
    ExtensionDispositionType => "extension-disposition-type"
  }
}

///|
/// Audits a parsed `ContentDisposition` for the RFC 6266 Section 7
/// concerns. Never raises; the issues are advisory.
pub fn audit_content_disposition(cd : ContentDisposition) -> AuditReport {
  let issues : Array[AuditIssue] = []
  let star = cd.filename_star()
  let plain = cd.filename()
  match (star, plain) {
    (None, None) => {
      issues.push(
        issue(AuditSeverity::Warning, AuditKind::MissingFilename, "", "no filename parameter is present"),
      )
    }
    (Some(_), None) => {
      issues.push(
        issue(
          AuditSeverity::Info,
          AuditKind::FilenameStarWithoutFallback,
          "filename*",
          "filename* is present without a plain filename fallback",
        ),
      )
    }
    (Some(_), Some(p)) => {
      issues.push(
        issue(
          AuditSeverity::Info,
          AuditKind::BothFilenameAndFilenameStar,
          "filename",
          "both filename and filename* are present; filename* takes precedence",
        ),
      )
      audit_filename_string(p, "filename", issues)
    }
    (None, Some(p)) => {
      issues.push(
        issue(
          AuditSeverity::Info,
          AuditKind::PlainFilenameOnly,
          "filename",
          "only the plain filename parameter is present",
        ),
      )
      audit_filename_string(p, "filename", issues)
    }
  }
  // Extended value concerns.
  match star {
    Some(ev) => audit_extended_value(ev, issues)
    None => ()
  }
  // Non-ASCII in the plain filename without an RFC 8187 companion.
  match plain {
    Some(p) => {
      if has_non_ascii(p) && star is None {
        issues.push(
          issue(
            AuditSeverity::Warning,
            AuditKind::MissingFilenameStarForNonAscii,
            "filename",
            "non-ASCII filename without an RFC 8187 filename*",
          ),
        )
      }
    }
    None => ()
  }
  // Duplicate parameters.
  let seen : Array[String] = []
  for p in cd.parameters() {
    let lower = p.name().to_lower()
    let mut dup = false
    for s in seen {
      if s == lower {
        dup = true
      }
    }
    if dup {
      issues.push(
        issue(AuditSeverity::Warning, AuditKind::DuplicateParameter, p.name(), "duplicate parameter"),
      )
    } else {
      seen.push(lower)
    }
  }
  // Extension disposition type.
  if cd.disposition_type().is_extension() {
    issues.push(
      issue(
        AuditSeverity::Info,
        AuditKind::ExtensionDispositionType,
        "",
        "disposition type is an extension type, not inline or attachment",
      ),
    )
  }
  {
    issues,
  }
}

///|
/// Turns the diagnostics of a detailed parse (duplicate names and compatible
/// recoveries) into audit issues.
pub fn audit_disposition_parse(parse : DispositionParse) -> AuditReport {
  let issues : Array[AuditIssue] = []
  for name in parse.duplicates() {
    issues.push(
      issue(AuditSeverity::Warning, AuditKind::DuplicateParameter, name, "duplicate parameter"),
    )
  }
  for recovery in parse.recoveries() {
    issues.push(
      issue(
        AuditSeverity::Warning,
        AuditKind::RecoveryApplied,
        "",
        "compatible recovery applied: \{recovery}",
      ),
    )
  }
  {
    issues,
  }
}

///|
/// Audits a filename against a policy. The issues mirror the sanitizer's
/// concerns; this is the advisory side, `sanitize_filename` is the
/// corrective side.
pub fn audit_filename(name : String, policy : FilenamePolicy) -> AuditReport {
  let issues : Array[AuditIssue] = []
  audit_filename_string(name, "filename", issues)
  if name.char_length() > policy.max_length() {
    issues.push(
      issue(
        AuditSeverity::Info,
        AuditKind::LongFilename,
        "filename",
        "filename exceeds the policy maximum length (\{policy.max_length()} code points)",
      ),
    )
  }
  if policy.windows_reserved().is_enabled() && is_windows_reserved_name(name) {
    issues.push(
      issue(
        AuditSeverity::High,
        AuditKind::ReservedWindowsName,
        "filename",
        "filename is a Windows reserved device name",
      ),
    )
  }
  {
    issues,
  }
}

///|
/// Audits a filename together with its declared media type. The media type
/// strengthens the extension-risk finding: an executable-looking extension
/// combined with an executable media type is High, on its own it is Warning.
pub fn audit_filename_with_media_type(
  name : String,
  media_type : String,
  policy : FilenamePolicy
) -> AuditReport {
  let report = audit_filename(name, policy)
  let ext = filename_extension(name)
  if risky_extension(ext) {
    let severity = if executable_media_type(media_type) {
      AuditSeverity::High
    } else {
      AuditSeverity::Warning
    }
    report.issues.push(
      issue(
        severity,
        AuditKind::ExtensionRisk,
        "filename",
        "extension '.{ext}' is in the executable/script risk list (media type: \{media_type})",
      ),
    )
  }
  report
}

///|
/// Audits a raw header value in one step: parse strictly, then combine the
/// parse diagnostics with the model audit. Errors when the value does not
/// parse.
pub fn audit_header(input : String) -> Result[AuditReport, DispositionError] {
  let parse = match parse_content_disposition_detailed(input, ParseOptions::default()) {
    Ok(p) => p
    Err(e) => return Err(e)
  }
  let issues : Array[AuditIssue] = []
  for i in audit_disposition_parse(parse).issues() {
    issues.push(i)
  }
  for i in audit_content_disposition(parse.content_disposition()).issues() {
    issues.push(i)
  }
  Ok({ issues: issues })
}

// Audits the plain string value of the `filename` parameter.
fn audit_filename_string(
  value : String,
  parameter : String,
  issues : Array[AuditIssue]
) -> Unit {
  if value == "" {
    issues.push(
      issue(AuditSeverity::Warning, AuditKind::EmptyFilename, parameter, "filename is empty"),
    )
    return
  }
  let bytes = @utf8.encode(value)
  let mut saw_separator = false
  let mut saw_control = false
  for i = 0; i < bytes.length(); i = i + 1 {
    if is_path_separator(bytes[i]) {
      saw_separator = true
    }
    if is_control_byte(bytes[i]) {
      saw_control = true
    }
  }
  if saw_separator {
    issues.push(
      issue(
        AuditSeverity::High,
        AuditKind::PathSeparatorInFilename,
        parameter,
        "filename contains a path separator",
      ),
    )
  }
  if saw_control {
    issues.push(
      issue(
        AuditSeverity::High,
        AuditKind::ControlCharacterInFilename,
        parameter,
        "filename contains a control character",
      ),
    )
  }
  if has_non_ascii(value) {
    issues.push(
      issue(
        AuditSeverity::Warning,
        AuditKind::NonAsciiUnquotedFilename,
        parameter,
        "filename contains non-ASCII bytes",
      ),
    )
  }
  if value.char_length() > 0 {
    let last = value[value.char_length() - 1]
    if last == '.' || last == ' ' {
      issues.push(
        issue(
          AuditSeverity::Warning,
          AuditKind::TrailingDotOrSpace,
          parameter,
          "filename ends in a dot or a space",
        ),
      )
    }
  }
}

// Audits an RFC 8187 extended value for charset/language concerns.
fn audit_extended_value(ev : ExtendedValue, issues : Array[AuditIssue]) -> Unit {
  if !is_supported_charset(ev.charset()) {
    issues.push(
      issue(
        AuditSeverity::High,
        AuditKind::UnsupportedCharset,
        "filename*",
        "unsupported charset: \{ev.charset()}",
      ),
    )
  }
  match ev.language() {
    Some(lang) => {
      if !valid_language_tag(lang) {
        issues.push(
          issue(
            AuditSeverity::Warning,
            AuditKind::InvalidLanguageTag,
            "filename*",
            "invalid language tag: \{lang}",
          ),
        )
      }
    }
    None => ()
  }
}

// Whether a string contains non-ASCII bytes.
fn has_non_ascii(value : String) -> Bool {
  let bytes = @utf8.encode(value)
  for i = 0; i < bytes.length(); i = i + 1 {
    if is_obs_text(bytes[i]) {
      return true
    }
  }
  false
}

// The extension of a filename (after the last dot, lower-cased), or "".
fn filename_extension(name : String) -> String {
  match last_dot_index(name) {
    Some(i) => name[(i + 1):].to_owned().to_lower()
    None => ""
  }
}

// Whether an extension is in the executable/script risk list.
fn risky_extension(ext : String) -> Bool {
  let risky = ["exe", "com", "bat", "cmd", "msi", "dll", "scr", "pif", "vbs", "js", "jse", "sh", "lnk"]
  for r in risky {
    if ext == r {
      return true
    }
  }
  false
}

// Whether a media type should be treated as executable/script-capable.
fn executable_media_type(media_type : String) -> Bool {
  let mt = media_type.to_lower()
  mt == "application/x-msdownload" || mt == "application/octet-stream" ||
    mt.has_prefix("application/x-ms") || mt == "text/html" || mt == "application/javascript" ||
    mt == "application/x-javascript" || mt.has_prefix("application/x-executable") ||
    mt == "application/vnd.microsoft.portable-executable" || mt == "application/x-sh"
}

fn issue(
  severity : AuditSeverity,
  kind : AuditKind,
  parameter : String,
  message : String
) -> AuditIssue {
  { severity, kind, parameter, message }
}

// Numeric rank for severity filtering.
fn severity_rank(severity : AuditSeverity) -> Int {
  match severity {
    Info => 0
    Warning => 1
    High => 2
  }
}
