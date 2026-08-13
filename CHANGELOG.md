# Changelog

All notable changes to `moon-content-disposition` are recorded here. The
version is kept in one place: `library_version()` in `model.mbt`, mirrored by
`moon.mod`.

## [0.1.1] — 2026-08-13

### Changed

- Add `repository` field to `moon.mod` so the mooncakes.io page links back to
  the GitHub source.

## [0.1.0] — Initial release

First release. Everything below is implemented, tested, and
verified on the `native`, `js` and `wasm-gc` targets (327 tests, 25 files).

### Added — parsing

- RFC 6266 §4.2 header-value parser: `inline` / `attachment` / extension
  disposition types, `filename`, `filename*` and `disp-ext-parm` parameters,
  optional OWS around `;` and `=`.
- Two parse modes: `ParseMode::Strict` (default) and `ParseMode::Compatible`
  with five individually documented recoveries
  (`skip-empty-parameter`, `trailing-semicolon`, `empty-parameter-value`,
  `legacy-unquoted-non-ascii-value`, `quoted-extended-value`), each recorded
  in the parse result and surfaced in the audit.
- Duplicate parameter handling: rejected in strict mode, preserved and
  recorded in compatible mode.
- Seven independent `Limits` with `default` / `strict` / `permissive`
  presets; over-limit is an error, never a silent truncation.
- Structured `DispositionError`: 13 stages, 22 kinds, UTF-8 byte offset, and a
  bounded context excerpt.

### Added — RFC 8187 international filenames

- `filename*` extended-value parsing and serialisation for `UTF-8` and
  `ISO-8859-1`, with strict `%HH` validation, RFC 5646 language-tag checks,
  and deterministic re-encoding (uppercase hex).
- RFC 6266 §4.3 filename resolution: `filename*` wins, `filename` is the
  fallback; advisory warnings for separators, control characters and empty
  names.

### Added — safe filenames

- `FilenamePolicy` with three profiles (`Portable`, `WindowsLike`,
  `PosixLike`), extension policy and Windows reserved-name defusing.
- `sanitize_filename` / `sanitize_portable_filename`: single-path-component
  guarantees, `.`/`..` defusing, trailing-dot/space trimming, length
  truncation, idempotence, and stable issue keys. A non-empty input never
  fails.
- `audit_header` / `audit_content_disposition` / `audit_filename[_with_media_type]`:
  18 `AuditKind`s with `Info`/`Warning`/`High` severities and
  consumer-friendly severity counters.

### Added — serialisation and generation

- Deterministic `serialize_content_disposition` and a preserve-case variant
  that reproduces the original wire token and casing.
- `canonicalize_content_disposition`: canonical lowercase, `filename` before
  `filename*`, deterministic encoding, idempotent.
- `generate_attachment` / `generate_inline` (+ `_with_options`): quoted
  `filename` always, `filename*` for non-ASCII, CR/LF/NUL injection defence.

### Added — tooling

- `disposition-tool` executable: 11 commands, JSON output, no `unwrap`, exit
  status 1 on failure; works on all three targets (argv shapes normalised per
  backend).
- Six runnable examples: `parse`, `resolve`, `sanitize`, `generate`,
  `canonicalize`, `audit`.
- Documentation set under `docs/`, plus `scripts/verify_all.ps1` and
  `scripts/count_code.py`.

### Testing

- 327 named tests across 25 files, all green on `native`, `js` and `wasm-gc`.
- Deterministic property suite: 2600+ property cases, 1300 sanitizer
  invariants, 600 canonicalisation cases (seeded PRNG, reproducible forever).
- Truncation-safety, injection, security and round-trip suites.

### Notes

- Initial release. Hosted at
  <https://github.com/xiaojing012/moon-content-disposition>. No affiliation is
  claimed with any organisation.
- This build targets MoonBit `0.1.20260713`.
