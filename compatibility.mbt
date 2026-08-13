// compatibility.mbt — Compatible-mode recovery bookkeeping.
//
// `ParseMode::Compatible` accepts a small, individually documented set of
// real-world deviations from the strict grammar. Every compatible recovery
// that is actually applied during a parse is recorded on a
// `ParseCollector`, surfaces in the detailed parse result, and is turned
// into an `RecoveryApplied` audit issue — so no deviation is silent.
//
// The complete list of recoveries, with reasons, risks and test names, is
// documented in `docs/compatibility.md`. The names below are the stable
// keys used in the parse result and the audit report.

///|
/// The stable names of every compatible-mode recovery this library can
/// apply, in documentation order. See `docs/compatibility.md`.
pub fn compatible_recovery_names() -> Array[String] {
  let names : Array[String] = []
  names.push("skip-empty-parameter")
  names.push("trailing-semicolon")
  names.push("empty-parameter-value")
  names.push("legacy-unquoted-non-ascii-value")
  names.push("quoted-extended-value")
  names
}

///|
/// Mutable bookkeeping used while parsing one Content-Disposition value:
/// the compatible recoveries applied, the names of duplicated parameters
/// (preserved in compatible mode), and the parameter names seen so far
/// (used for duplicate detection).
pub struct ParseCollector {
  recoveries : Array[String]
  duplicates : Array[String]
  seen_names : Array[String]
}

///|
/// Constructs an empty collector.
pub fn ParseCollector::new() -> ParseCollector {
  { recoveries: Array::new(), duplicates: Array::new(), seen_names: Array::new() }
}

///|
/// Records a compatible recovery by stable name, deduplicating so that a
/// recovery is reported at most once per parse.
pub fn ParseCollector::record_recovery(self : ParseCollector, note : String) -> Unit {
  for existing in self.recoveries {
    if existing == note {
      return
    }
  }
  self.recoveries.push(note)
}

///|
/// The recoveries applied during the parse, in application order (each
/// name at most once).
pub fn ParseCollector::recoveries(self : ParseCollector) -> Array[String] {
  self.recoveries
}

///|
/// The names of duplicated parameters, in first-duplicate-detection order
/// (each name at most once).
pub fn ParseCollector::duplicates(self : ParseCollector) -> Array[String] {
  self.duplicates
}

///|
/// Records a duplicated parameter name (compatible mode only).
pub fn ParseCollector::record_duplicate(self : ParseCollector, name : String) -> Unit {
  for existing in self.duplicates {
    if existing.equal_ignore_ascii_case(name) {
      return
    }
  }
  self.duplicates.push(name)
}

///|
/// Whether a parameter name has already been seen during this parse.
pub fn ParseCollector::has_seen(self : ParseCollector, name : String) -> Bool {
  for existing in self.seen_names {
    if existing.equal_ignore_ascii_case(name) {
      return true
    }
  }
  false
}

///|
/// Marks a parameter name as seen.
pub fn ParseCollector::mark_seen(self : ParseCollector, name : String) -> Unit {
  self.seen_names.push(name)
}
