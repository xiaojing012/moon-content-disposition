// filename_sanitize.mbt — Policy-driven filename sanitisation.
//
// A download filename comes from an HTTP header and must never be used as a
// filesystem path without being sanitised first: the header is untrusted
// input. This module turns a raw filename (usually the output of
// `resolve_filename`) into a safe filesystem name by applying a
// `FilenamePolicy`. The result is always a single path component:
//
//   - no path separators survive (`/` and `\` are replaced per profile);
//   - the whole-name forms `.` and `..` are defused;
//   - Windows reserved device names (`CON`, `PRN`, ...) are defused when the
//     policy enables it;
//   - Windows-forbidden characters are removed per profile;
//   - trailing dots and spaces are trimmed when the profile calls for it;
//   - the name is truncated to the policy's maximum length.
//
// Every transformation is recorded as a stable issue key in
// `SafeFilenameResult::issues`, so a caller can log why a name changed.
// There is deliberately no transliteration: a non-portable character is
// replaced with `_`, never "sounded out" into ASCII.

///|
/// The result of sanitising a filename: the original value, the safe value,
/// whether anything changed, and the list of issues (each stable key at most
/// once).
pub struct SafeFilenameResult {
  original : String
  safe : String
  changed : Bool
  issues : Array[String]
}

///|
/// The original (unsanitised) filename.
pub fn SafeFilenameResult::original(self : SafeFilenameResult) -> String {
  self.original
}

///|
/// The sanitised filename, safe to use as a single path component.
pub fn SafeFilenameResult::safe(self : SafeFilenameResult) -> String {
  self.safe
}

///|
/// Whether the sanitised name differs from the original.
pub fn SafeFilenameResult::changed(self : SafeFilenameResult) -> Bool {
  self.changed
}

///|
/// The stable issue keys produced while sanitising, each at most once:
/// `replaced-path-separator`, `replaced-unsafe-character`,
/// `defused-dot-name`, `prefixed-reserved-name`, `trimmed-trailing-char`,
/// `truncated-to-max-length`, `denied-extension`,
/// `extension-not-in-allow-list`.
pub fn SafeFilenameResult::issues(self : SafeFilenameResult) -> Array[String] {
  self.issues
}

///|
/// Sanitises a filename with the default (`Portable`) policy. Equivalent to
/// `sanitize_filename(name, FilenamePolicy::default())`.
///
/// Errors: `FilenamePolicy::UnsafeFilename` when the input is empty.
pub fn sanitize_portable_filename(name : String) -> Result[SafeFilenameResult, DispositionError] {
  sanitize_filename(name, FilenamePolicy::default())
}

///|
/// Sanitises a filename with an explicit policy. The returned name is a
/// single path component: it contains no `/` or `\` and cannot be `.` or
/// `..`, and it is never empty or a dot-only name. A non-empty input always
/// produces a safe name (`.` and `..` become `_`; a name made only of dots
/// and spaces falls back to `_`). See `FilenamePolicy` for the per-profile
/// character rules.
///
/// Errors: `FilenamePolicy::UnsafeFilename` when the input is empty.
pub fn sanitize_filename(
  name : String,
  policy : FilenamePolicy
) -> Result[SafeFilenameResult, DispositionError] {
  if name.char_length() == 0 {
    return Err(
      disposition_error(FilenamePolicy, UnsafeFilename, "cannot sanitise an empty filename"),
    )
  }
  let issues : Array[String] = []
  let profile = policy.profile()

  // 1. Defuse the whole-name forms `.` and `..` on the raw name. This must
  //    happen before the trailing trim: `.` and `..` are made only of dots,
  //    so trimming first would erase them.
  let mut working = name
  if working == "." || working == ".." {
    working = "_" + working
    push_issue(issues, "defused-dot-name")
  }

  // 2. Trim trailing dots and spaces from the raw name (Portable and
  //    WindowsLike profiles). A Windows filesystem silently drops trailing
  //    dots and spaces, so "CON " is the reserved name "CON"; trimming before
  //    the character pass also keeps a trailing space a trim rather than a
  //    replacement with `_`.
  if profile != PosixLike {
    let pre_trimmed = trim_trailing_dot_space(working)
    if pre_trimmed != working {
      working = pre_trimmed
      push_issue(issues, "trimmed-trailing-char")
    }
  }

  // 3. Character-level replacement.
  let sb = StringBuilder()
  for ch in working {
    if profile_safe_char(profile, ch) {
      sb.write_char(ch)
    } else {
      sb.write_char('_')
      if ch == '/' || ch == '\\' {
        push_issue(issues, "replaced-path-separator")
      } else {
        push_issue(issues, "replaced-unsafe-character")
      }
    }
  }
  let mut safe = sb.to_string()

  // 4. Defuse Windows reserved device names.
  if policy.windows_reserved().is_enabled() && is_windows_reserved_name(safe) {
    safe = "_" + safe
    push_issue(issues, "prefixed-reserved-name")
  }

  // 5. Trim trailing dots and spaces once more (Portable and WindowsLike
  //    profiles), in case a replacement left one.
  if profile != PosixLike {
    let trimmed = trim_trailing_dot_space(safe)
    if trimmed != safe {
      safe = trimmed
      push_issue(issues, "trimmed-trailing-char")
    }
  }

  // 6. Truncate to the policy maximum length.
  let cap = if policy.max_length() < 1 { 1 } else { policy.max_length() }
  if safe.char_length() > cap {
    safe = safe[:cap].to_owned()
    push_issue(issues, "truncated-to-max-length")
  }

  // 7. Truncation cuts mid-string, which can reintroduce a defusable whole
  //    name, a Windows reserved name, or a trailing dot/space. Normalise
  //    once more so the result is a single stable safe path component:
  //    sanitising the result of a sanitisation is a no-op.
  if safe == "." || safe == ".." {
    safe = "_" + safe
    push_issue(issues, "defused-dot-name")
  }
  if policy.windows_reserved().is_enabled() && is_windows_reserved_name(safe) {
    safe = "_" + safe
    push_issue(issues, "prefixed-reserved-name")
  }
  if profile != PosixLike {
    let stable = trim_trailing_dot_space(safe)
    if stable != safe {
      safe = stable
      push_issue(issues, "trimmed-trailing-char")
    }
  }

  // 8. A sanitised name must not be empty: a name made only of dots and
  //    spaces (for example " .") is trimmed to nothing, so fall back to `_`
  //    rather than failing.
  if safe.char_length() == 0 {
    safe = "_"
    push_issue(issues, "replaced-unsafe-character")
  }

  // 9. Advisory extension audit (never an error).
  audit_extension(safe, policy, issues)

  Ok({ original: name, safe, changed: safe != name, issues })
}

// Whether a code point survives the profile's character rule.
fn profile_safe_char(profile : PolicyProfile, ch : Char) -> Bool {
  match profile {
    Portable => portable_safe_char(ch)
    WindowsLike => windows_safe_char(ch)
    PosixLike => posix_safe_char(ch)
  }
}

// Portable: only `A-Za-z0-9._-`.
fn portable_safe_char(ch : Char) -> Bool {
  let v = ch.to_int()
  (v >= 48 && v <= 57) || (v >= 65 && v <= 90) || (v >= 97 && v <= 122) ||
    ch == '.' || ch == '_' || ch == '-'
}

// Windows: forbid C0 controls, DEL and `< > : " / \ | ? *`.
fn windows_safe_char(ch : Char) -> Bool {
  let v = ch.to_int()
  if v < 32 || v == 127 {
    return false
  }
  ch != '<' && ch != '>' && ch != ':' && ch != '"' && ch != '/' && ch != '\\' &&
    ch != '|' && ch != '?' && ch != '*'
}

// Posix: only `/` and NUL are forbidden.
fn posix_safe_char(ch : Char) -> Bool {
  ch != '/' && ch.to_int() != 0
}

// Whether a sanitised name is a Windows reserved device name (the stem, the
// part before the first dot, uppercased, matches CON/PRN/AUX/NUL or
// COM1-9/LPT1-9).
fn is_windows_reserved_name(name : String) -> Bool {
  let stem = match name.split_once(".") {
    Some((s, _)) => s.to_owned()
    None => name
  }
  let upper = stem.to_upper()
  if upper == "CON" || upper == "PRN" || upper == "AUX" || upper == "NUL" {
    return true
  }
  if upper.char_length() == 4 && (upper.has_prefix("COM") || upper.has_prefix("LPT")) {
    let last = upper[3].to_int()
    if last >= 49 && last <= 57 {
      return true
    }
  }
  false
}

// Removes trailing '.' and ' ' characters.
fn trim_trailing_dot_space(name : String) -> String {
  let mut end = name.char_length()
  while end > 0 {
    let c = name[end - 1]
    if c == '.' || c == ' ' {
      end = end - 1
    } else {
      break
    }
  }
  name[:end].to_owned()
}

// The index of the last '.' in a name, or `None`.
fn last_dot_index(name : String) -> Int? {
  let mut idx : Int? = None
  for i = 0; i < name.char_length(); i = i + 1 {
    if name[i] == '.' {
      idx = Some(i)
    }
  }
  idx
}

// Appends an issue key at most once.
fn push_issue(issues : Array[String], key : String) -> Unit {
  for existing in issues {
    if existing == key {
      return
    }
  }
  issues.push(key)
}

// Compares an extension against a list entry: both are lower-cased and a
// leading dot is stripped.
fn ext_matches(ext : String, entry : String) -> Bool {
  let normalized = if entry.char_length() > 0 && entry[0] == '.' {
    entry[1:].to_owned().to_lower()
  } else {
    entry.to_lower()
  }
  ext == normalized
}

// Records advisory extension issues (never errors).
fn audit_extension(
  safe : String,
  policy : FilenamePolicy,
  issues : Array[String]
) -> Unit {
  let ext_policy = policy.extension()
  if !ext_policy.is_enabled() {
    return
  }
  match last_dot_index(safe) {
    Some(i) => {
      let ext = safe[(i + 1):].to_owned().to_lower()
      for entry in ext_policy.deny_list() {
        if ext_matches(ext, entry) {
          push_issue(issues, "denied-extension")
        }
      }
      let allow = ext_policy.allow_list()
      if !allow.is_empty() {
        let mut allowed = false
        for entry in allow {
          if ext_matches(ext, entry) {
            allowed = true
          }
        }
        if !allowed {
          push_issue(issues, "extension-not-in-allow-list")
        }
      }
    }
    None => ()
  }
}
