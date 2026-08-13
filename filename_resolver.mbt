// filename_resolver.mbt — Selecting the download filename from a parsed
// Content-Disposition value.
//
// RFC 6266 Section 4.3 defines the precedence: when both `filename*` and
// `filename` are present, the value of `filename*` (RFC 8187, decoded) takes
// precedence and `filename` acts as a fallback for recipients that do not
// implement RFC 8187. `resolve_filename` implements exactly that rule. It is
// a pure *selection* function: it does not sanitise. The value it returns
// should be run through `sanitize_portable_filename` (or a policy of your
// choice) before it is used as a filesystem name.
//
// Resolving is never security-critical on its own: the warnings it reports
// (path separators, control characters, empty names) are advisory and must
// be acted on by the sanitizer.

///|
/// Where the selected filename came from.
pub enum FilenameSource {
  /// The plain `filename` parameter.
  Filename
  /// The RFC 8187 `filename*` parameter (decoded).
  FilenameStar
}

///|
/// The result of resolving a download filename from a `ContentDisposition`:
/// the selected value, its source, whether a fallback was available, and any
/// advisory warnings.
pub struct FilenameSelection {
  selected : String
  source : FilenameSource
  fallback : Bool
  warnings : Array[String]
}

///|
/// The selected filename value.
pub fn FilenameSelection::selected(self : FilenameSelection) -> String {
  self.selected
}

///|
/// Whether the value came from `filename` or `filename*`.
pub fn FilenameSelection::source(self : FilenameSelection) -> FilenameSource {
  self.source
}

///|
/// Whether a fallback value was present (a plain `filename` alongside a
/// `filename*`).
pub fn FilenameSelection::fallback(self : FilenameSelection) -> Bool {
  self.fallback
}

///|
/// The advisory warnings produced while resolving, each at most once. The
/// stable keys are `no-filename-parameter` (not produced here — that is an
/// error), `filename-star-precedence`, `empty-filename`,
/// `contains-path-separator` and `contains-control-character`.
pub fn FilenameSelection::warnings(self : FilenameSelection) -> Array[String] {
  self.warnings
}

///|
/// Resolves the download filename from a `ContentDisposition`, applying the
/// RFC 6266 Section 4.3 precedence rule: `filename*` wins over `filename`.
///
/// Errors: `FilenameResolution::InvalidFilename` when neither `filename` nor
/// `filename*` is present.
pub fn resolve_filename(cd : ContentDisposition) -> Result[FilenameSelection, DispositionError] {
  let star = cd.filename_star()
  let plain = cd.filename()
  let warnings : Array[String] = []
  let mut selected = ""
  let source = if star is Some(_) {
    let ev = star.unwrap()
    selected = ev.value()
    if plain is Some(_) {
      push_warning(warnings, "filename-star-precedence")
    }
    if selected == "" {
      push_warning(warnings, "empty-filename")
    }
    FilenameStar
  } else {
    match plain {
      Some(v) => {
        selected = v
        if selected == "" {
          push_warning(warnings, "empty-filename")
        }
        Filename
      }
      None =>
        return Err(
          disposition_error(
            FilenameResolution,
            InvalidFilename,
            "neither 'filename' nor 'filename*' is present",
          ),
        )
    }
  }
  let bytes = @utf8.encode(selected)
  for i = 0; i < bytes.length(); i = i + 1 {
    if is_path_separator(bytes[i]) {
      push_warning(warnings, "contains-path-separator")
    } else if is_control_byte(bytes[i]) {
      push_warning(warnings, "contains-control-character")
    }
  }
  Ok({ selected, source, fallback: plain is Some(_) && star is Some(_), warnings })
}

// Appends a warning key at most once.
fn push_warning(warnings : Array[String], key : String) -> Unit {
  for existing in warnings {
    if existing == key {
      return
    }
  }
  warnings.push(key)
}
