# Security model

Content-Disposition is the header that decides where an HTTP response gets
saved. RFC 6266 Section 7 spells out the ways that can go wrong, and this
library treats the header as **untrusted input** throughout. This page
collects the defences, what they guarantee, and what they deliberately do not
claim.

## Threat model

The attacker controls the `Content-Disposition` value. The library is used by a
recipient (a browser, a download manager, a server-side content pipeline). The
goals of the attacker, and the corresponding defences:

| Attacker goal | Defence |
| --- | --- |
| Path traversal — write outside the target directory | sanitizer removes `/` and `\`; whole-name `.`/`..` defused; resolve→sanitize is the mandated pipeline |
| Header injection — smuggle CR/LF to add headers or fields | generator **rejects** CR/LF/NUL/control bytes; parser never treats CR/LF as whitespace |
| Resource exhaustion — multi-megabyte header, thousands of parameters | seven independent `Limits`; over-limit is an error, never a silent truncation |
| Confusing/ambiguous filenames — `filename` vs `filename*`, non-ASCII mojibake | RFC 6266 §4.3 precedence implemented; audit reports missing `filename*` for non-ASCII |
| Windows device-name tricks — `CON`, `PRN`, trailing-dot/space abuse | `FilenamePolicy::windows_reserved` defusing; trailing dot/space trimming (Portable/WindowsLike) |
| File-extension confusion — `install.exe` delivered as `text/plain` | `audit_filename_with_media_type` escalates executable extensions to High |
| Duplicate/extension parameters used to smuggle state | duplicates rejected in strict mode, recorded in compatible mode, audited |

## Injection defence (CR/LF/NUL)

- The **generator** (`generate_attachment` / `generate_inline` and their
  `_with_options` variants) returns
  `QuotedString::InvalidControlCharacter` when the filename contains CR, LF,
  NUL or any control byte. A control byte never reaches the wire.
- The **parser** treats only SP and HTAB as whitespace. CR and LF terminate or
  fail the parse — they are never folded into a value.
- The **sanitizer** replaces control characters with `_` (Portable/WindowsLike
  profiles) or keeps them (PosixLike) but the audit layer always reports
  `control-character-in-filename` (High).

## Resource limits

`Limits` bounds seven quantities. The parser checks the input byte count before
scanning, the parameter count while scanning, and the per-name/per-value byte
bounds while each parameter is read. The resolver, policy and generator also
respect `max_filename_bytes`.

- Over-limit → `DispositionErrorKind::LimitExceeded` at the `Limit` or `Input`
  stage. It is an **error**, never a silent truncation. No parse can loop
  forever or allocate without bound.
- `max_context_bytes` bounds every error `context()` excerpt and every scanner
  context window, so a malformed megabyte header never gets echoed in full.
- Three presets cover the common cases: `Limits::default()` (1 MiB input /
  256 parameters / 8 KiB values), `Limits::strict()` (16 KiB / 32 / 1 KiB),
  `Limits::permissive()` (64 MiB / 4096 / 4 MiB).

## Sanitisation guarantees

`sanitize_filename(name, policy)` returns a value that is safe to use as a
**single path component**:

- it contains no `/` and no `\` (per profile; PosixLike replaces `/`, all
  profiles are parameterised by the policy);
- it is never `.` or `..` (defused to `_.` / `_..`);
- it is never empty (a name made only of dots and spaces falls back to `_`);
- a **non-empty input never errors** — the only error is
  `FilenamePolicy::UnsafeFilename` for an empty input;
- the result is stable: sanitising the result of a sanitisation is a no-op.

Every transformation is recorded as a stable issue key in
`SafeFilenameResult::issues`, so a caller can log *why* a name changed.

## What is deliberately NOT claimed

- **No "100% RFC compliance" guarantee.** The library implements the RFC 6266
  and RFC 8187 grammars as documented here; edge cases the RFC leaves open
  (duplicate parameters, obs-text, empty parameters) are decided explicitly and
  documented in [compatibility.md](compatibility.md).
- **No magic sanitisation.** A policy cannot invent meaning: `café` is never
  transliterated to `cafe`. Non-portable characters become `_`. If the correct
  safe name requires a human decision, the audit report is the tool that flags
  it; the sanitizer is not a substitute for application policy.
- **`resolve_filename` is not a sanitizer.** It *selects* a value and *warns*;
  the caller must run it through `sanitize_filename`. Using the resolved name
  directly as a path is a caller error, not a library feature.
- **The audit is advisory.** `AuditReport` never raises and never changes the
  value; acting on High-severity issues is the caller's policy decision.

## Structured errors

Every public function returns `Result[T, DispositionError]`. The error carries:

- `stage()` — one of 13 processing stages (e.g. `QuotedString`, `PercentEncoding`);
- `kind()` — one of 22 stable kinds (e.g. `InvalidUtf8`, `UnsafeFilename`);
- `offset()` — the UTF-8 byte offset into the exact input passed to the entry
  point (0 when not meaningful);
- `context()` — a short, truncated excerpt of the input at the failure point.

Error handling is exhaustive: there is no `unwrap` at any public boundary, so a
malformed header can never panic a caller.

## Truncation safety

All of the following are exercised by tests:

- an error context never echoes a 2 KiB input (bounded to `max_context_bytes`);
- a value just over a limit is rejected, not cut off;
- long quoted strings round-trip without silent truncation;
- `to_display()` is a single bounded line.
