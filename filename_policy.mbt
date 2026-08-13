// filename_policy.mbt — The policy that drives filename sanitisation.
//
// Sanitising a download filename is a policy decision, not a single
// algorithm. This module defines three named profiles that cover the common
// cases, each documented for what it allows and rejects:
//
//   - `Portable` — the strictest profile. Only `A-Za-z0-9._-` survive;
//     everything else (including space and all non-ASCII) becomes `_`.
//     Windows reserved names are defused and trailing dots are trimmed. Use
//     this as the default for names that may travel between operating
//     systems (the value of `sanitize_portable_filename`).
//   - `WindowsLike` — matches what a Windows filesystem can safely store:
//     every code point is kept except the characters Windows forbids
//     (`< > : " / \ | ? *` and C0 controls), reserved names are defused,
//     and trailing dots/spaces are trimmed.
//   - `PosixLike` — the most permissive: only `/` (path separator) and NUL
//     are replaced. Everything else, including newlines and non-ASCII, is
//     kept. Reserved names and trailing-dot trimming are NOT applied.
//
// The per-profile character rules are implemented in filename_sanitize.mbt
// (`profile_safe_char`); the policy itself carries the knobs every caller
// needs: maximum length, extension auditing and Windows reserved-name
// handling. No profile performs transliteration — a non-portable character
// is replaced with `_`, never "sounded out" into ASCII.

///|
/// The three named sanitisation profiles.
pub enum PolicyProfile {
  /// Strict: only `A-Za-z0-9._-` are kept, everything else becomes `_`.
  Portable
  /// Windows-friendly: keeps most code points, forbids Windows-illegal
  /// characters, defuses reserved names and trailing dots/spaces.
  WindowsLike
  /// Permissive: replaces only `/` and NUL.
  PosixLike
} derive(Eq)

///|
/// Whether an extension is audited. When enabled, the sanitizer checks the
/// filename's extension against an allow list and/or a deny list and records
/// an issue (never an error) for a violation.
pub struct ExtensionPolicy {
  enabled : Bool
  allow_list : Array[String]
  deny_list : Array[String]
}

///|
/// An extension policy with auditing disabled.
pub fn ExtensionPolicy::disabled() -> ExtensionPolicy {
  { enabled: false, allow_list: [], deny_list: [] }
}

///|
/// An extension policy with auditing enabled. Extensions are compared
/// case-insensitively, with or without the leading dot (`"exe"` and
/// `".exe"` both match `exe`).
pub fn ExtensionPolicy::enabled(
  allow_list : Array[String],
  deny_list : Array[String]
) -> ExtensionPolicy {
  { enabled: true, allow_list, deny_list }
}

///|
/// Whether extension auditing is enabled.
pub fn ExtensionPolicy::is_enabled(self : ExtensionPolicy) -> Bool {
  self.enabled
}

///|
/// The allow list (compared case-insensitively).
pub fn ExtensionPolicy::allow_list(self : ExtensionPolicy) -> Array[String] {
  self.allow_list
}

///|
/// The deny list (compared case-insensitively).
pub fn ExtensionPolicy::deny_list(self : ExtensionPolicy) -> Array[String] {
  self.deny_list
}

///|
/// Whether Windows reserved-name defusing is applied.
pub struct WindowsReservedPolicy {
  enabled : Bool
}

///|
/// A Windows reserved-name policy with defusing enabled.
pub fn WindowsReservedPolicy::enabled() -> WindowsReservedPolicy {
  { enabled: true }
}

///|
/// A Windows reserved-name policy with defusing disabled.
pub fn WindowsReservedPolicy::disabled() -> WindowsReservedPolicy {
  { enabled: false }
}

///|
/// Whether reserved-name defusing is enabled.
pub fn WindowsReservedPolicy::is_enabled(self : WindowsReservedPolicy) -> Bool {
  self.enabled
}

///|
/// A complete sanitisation policy.
pub struct FilenamePolicy {
  profile : PolicyProfile
  max_length : Int
  extension : ExtensionPolicy
  windows_reserved : WindowsReservedPolicy
}

///|
/// The default policy: `Portable`, 255 characters, extension auditing off,
/// Windows reserved-name defusing on.
pub fn FilenamePolicy::default() -> FilenamePolicy {
  FilenamePolicy::portable()
}

///|
/// The `Portable` profile.
pub fn FilenamePolicy::portable() -> FilenamePolicy {
  {
    profile: Portable,
    max_length: 255,
    extension: ExtensionPolicy::disabled(),
    windows_reserved: WindowsReservedPolicy::enabled(),
  }
}

///|
/// The `WindowsLike` profile.
pub fn FilenamePolicy::windows_like() -> FilenamePolicy {
  {
    profile: WindowsLike,
    max_length: 255,
    extension: ExtensionPolicy::disabled(),
    windows_reserved: WindowsReservedPolicy::enabled(),
  }
}

///|
/// The `PosixLike` profile.
pub fn FilenamePolicy::posix_like() -> FilenamePolicy {
  {
    profile: PosixLike,
    max_length: 255,
    extension: ExtensionPolicy::disabled(),
    windows_reserved: WindowsReservedPolicy::disabled(),
  }
}

///|
/// The profile of this policy.
pub fn FilenamePolicy::profile(self : FilenamePolicy) -> PolicyProfile {
  self.profile
}

///|
/// The maximum length in code points. Names longer than this are truncated.
pub fn FilenamePolicy::max_length(self : FilenamePolicy) -> Int {
  self.max_length
}

///|
/// The extension auditing rule of this policy.
pub fn FilenamePolicy::extension(self : FilenamePolicy) -> ExtensionPolicy {
  self.extension
}

///|
/// The Windows reserved-name rule of this policy.
pub fn FilenamePolicy::windows_reserved(self : FilenamePolicy) -> WindowsReservedPolicy {
  self.windows_reserved
}

///|
/// A copy of this policy with a different maximum length.
pub fn FilenamePolicy::with_max_length(self : FilenamePolicy, max_length : Int) -> FilenamePolicy {
  { profile: self.profile, max_length, extension: self.extension, windows_reserved: self.windows_reserved }
}

///|
/// A copy of this policy with a different extension auditing rule.
pub fn FilenamePolicy::with_extension(self : FilenamePolicy, extension : ExtensionPolicy) -> FilenamePolicy {
  { profile: self.profile, max_length: self.max_length, extension, windows_reserved: self.windows_reserved }
}

///|
/// A copy of this policy with a different Windows reserved-name rule.
pub fn FilenamePolicy::with_windows_reserved(
  self : FilenamePolicy,
  windows_reserved : WindowsReservedPolicy
) -> FilenamePolicy {
  { profile: self.profile, max_length: self.max_length, extension: self.extension, windows_reserved }
}

///|
/// A stable programmatic name for a profile.
pub fn PolicyProfile::to_string(self : PolicyProfile) -> String {
  match self {
    Portable => "portable"
    WindowsLike => "windows-like"
    PosixLike => "posix-like"
  }
}
