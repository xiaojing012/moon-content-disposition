# API reference

Every public symbol lives in the library package `localdev/moon-content-disposition`.
All public functions that can fail return `Result[T, DispositionError]`; nothing
raises and nothing unwraps at a public boundary.

## Data model (`model.mbt`)

### Types

| Type | Meaning |
| --- | --- |
| `DispositionType` | `Inline` / `Attachment` / `Extension(String)` |
| `ParameterValue` | `Token(String)` / `Quoted(String)` / `Extended(ExtendedValue)` |
| `ExtendedValue` | `{ charset, language, value }` — a decoded RFC 8187 value |
| `DispositionParameter` | `{ name, value }` |
| `ContentDisposition` | `{ disposition_type, parameters, raw_disposition_type }` |

### Functions and methods

| Signature | Notes |
| --- | --- |
| `library_version() -> String` | The single source of truth for the version (`"0.1.0-dev"`). |
| `extended_value(charset, language, value) -> ExtendedValue` | Constructor. |
| `disposition_parameter(name, value) -> DispositionParameter` | Constructor. |
| `content_disposition(disposition_type) -> ContentDisposition` | Constructor, no parameters, no raw type. |
| `content_disposition_with_raw(disposition_type, raw) -> ContentDisposition` | Parser constructor that remembers the wire token. |
| `ContentDisposition::disposition_type() -> DispositionType` | |
| `ContentDisposition::raw_disposition_type() -> String?` | `Some` only for parsed values. |
| `ContentDisposition::parameters() -> Array[DispositionParameter]` | Input order. |
| `ContentDisposition::parameter_count() -> Int` | |
| `ContentDisposition::get_parameter(name) -> DispositionParameter?` | First match, case-insensitive. |
| `ContentDisposition::filename() -> String?` | Value of the last plain `filename`. |
| `ContentDisposition::filename_star() -> ExtendedValue?` | Decoded value of the last `filename*`. |
| `DispositionType::to_lower_name() -> String` | `"inline"` / `"attachment"` / lower-cased extension. |
| `DispositionType::is_inline() / is_attachment() / is_extension() -> Bool` | |
| `DispositionType::extension_name() -> String?` | |
| `DispositionType::matches(name) -> Bool` | Case-insensitive. |
| `DispositionParameter::name() -> String` / `value() -> ParameterValue` | |
| `DispositionParameter::is_extended() -> Bool` | Name ends with `*`. |
| `ParameterValue::plain() -> String?` | `Some` for token/quoted, `None` for extended. |
| `ParameterValue::extended() -> ExtendedValue?` | `Some` for extended. |
| `ParameterValue::is_extended() -> Bool` | |
| `ExtendedValue::charset() / language() / value()` | |
| `*::semantic_equal(other) -> Bool` | Structural equality (names case-insensitive). |
| `ContentDisposition::to_debug_string() -> String` | Compact human-readable rendering. |

## Parsing (`parser.mbt`, `options.mbt`, `limits.mbt`)

| Signature | Notes |
| --- | --- |
| `parse_content_disposition(input) -> Result[ContentDisposition, DispositionError]` | Strict, default limits. |
| `parse_content_disposition_with_options(input, options) -> Result[ContentDisposition, DispositionError]` | |
| `parse_content_disposition_detailed(input, options) -> Result[DispositionParse, DispositionError]` | Also returns duplicates and recoveries. |
| `DispositionParse::content_disposition() / duplicates() / recoveries() / mode()` | |

`ParseOptions` presets: `new()`, `default()` (strict + default limits),
`compatible()` (compatible + default limits), `strict()` (strict + strict
limits), `permissive()` (strict + permissive limits). Builders:
`with_mode`, `with_limits`. `ParseMode::to_string()` → `"strict"`/`"compatible"`.

`Limits` fields (all `Int`): `max_input_bytes`, `max_parameters`,
`max_parameter_name_bytes`, `max_parameter_value_bytes`, `max_filename_bytes`,
`max_extended_value_bytes`, `max_context_bytes`. Presets: `default()`
(1 MiB input / 256 parameters / 8 KiB value), `strict()` (16 KiB / 32 / 1 KiB),
`permissive()` (64 MiB / 4096 / 4 MiB).

## Errors (`error.mbt`)

`DispositionError` is a suberror with four accessors:

- `stage() -> DispositionErrorStage` — 13 stages: `Input`, `DispositionType`,
  `ParameterName`, `ParameterValue`, `Token`, `QuotedString`, `ExtendedValue`,
  `PercentEncoding`, `Charset`, `FilenameResolution`, `FilenamePolicy`,
  `Serialization`, `Limit`.
- `kind() -> DispositionErrorKind` — 22 kinds: `EmptyInput`,
  `InvalidDispositionType`, `ExpectedToken`, `UnexpectedCharacter`,
  `MissingEquals`, `MissingParameterValue`, `InvalidParameterName`,
  `DuplicateParameter`, `UnterminatedQuotedString`, `InvalidQuotedPair`,
  `InvalidControlCharacter`, `InvalidExtendedValue`, `MissingCharset`,
  `InvalidCharset`, `UnsupportedCharset`, `InvalidLanguage`,
  `InvalidPercentEncoding`, `InvalidUtf8`, `InvalidFilename`, `UnsafeFilename`,
  `LimitExceeded`, `TrailingInput`.
- `offset() -> Int` — UTF-8 byte offset into the input (`0` when not meaningful).
- `context() -> String` — bounded excerpt (≤ `max_context_bytes`), never the
  whole input.
- `to_display() -> String` — single-line rendering, e.g.
  `Input::EmptyInput at byte 0: empty Content-Disposition value`.

Both stage and kind have stable `to_string()` names for the CLI JSON output.

## Token / quoted-string / byte tables (`token.mbt`, `quoted_string.mbt`)

- `is_alpha`, `is_digit`, `is_hexdigit`, `token_char`, `is_token_char`,
  `is_ows_byte`, `is_control_byte`, `is_path_separator`, `is_obs_text`,
  `qdtext_char`, `quoted_pair_ok`, `is_separator_byte`, `hex_value`,
  `hex_char` — single-byte predicates over `Byte`.
- `validate_token(value) -> Bool` — the RFC 7230 `token` rule.
- `parse_quoted_string(...)`, `serialize_quoted_string(value) -> String`,
  `can_be_token(value) -> Bool`, `is_header_safe(value) -> Bool`.

## RFC 8187 (`rfc8187.mbt`, `percent_codec.mbt`, `charset.mbt`)

- `parse_extended_value(...)`, `parse_extended_value_string(...)`,
  `parse_extended_value_default(input) -> Result[ExtendedValue, DispositionError]`,
  `serialize_extended_value(ev) -> String` — deterministic re-encoding with
  uppercase hex.
- `attr_char(b) -> Bool`, `valid_language_tag(tag) -> Bool` — RFC 5646 shape
  (including private-use `x-` subtags).
- `percent_encode_attr_value(value) -> String`,
  `percent_decode_string(input) -> Result[String, DispositionError]`,
  `percent_decode_bytes(...)`, `has_percent_encoding(value) -> Bool`.
- `is_supported_charset(charset) -> Bool` — `UTF-8` / `ISO-8859-1`
  (case-insensitive).
- `canonical_charset(charset) -> String?`,
  `decode_bytes(charset, bytes) -> Result[String, DispositionError]`,
  `encode_to_bytes(charset, value) -> Result[Bytes, DispositionError]`,
  `fits_iso8859_1(value) -> Bool`.

## Serialisation and canonicalisation (`serializer.mbt`)

| Signature | Notes |
| --- | --- |
| `serialize_content_disposition(cd) -> Result[String, DispositionError]` | Canonical lowercase, model order. |
| `serialize_content_disposition_preserve_case(cd) -> Result[String, DispositionError]` | Round-trip helper; keeps original casing and the raw type token. |
| `canonicalize_content_disposition(input) -> Result[String, DispositionError]` | Parse → re-serialise with `filename` before `filename*`; idempotent. |

## Filename resolution (`filename_resolver.mbt`)

| Signature | Notes |
| --- | --- |
| `resolve_filename(cd) -> Result[FilenameSelection, DispositionError]` | RFC 6266 §4.3 precedence. Errors `FilenameResolution::InvalidFilename` when neither `filename` nor `filename*` is present. |
| `FilenameSelection::selected() -> String` | The chosen value. |
| `FilenameSelection::source() -> FilenameSource` | `Filename` or `FilenameStar`. |
| `FilenameSelection::fallback() -> Bool` | A plain `filename` was available. |
| `FilenameSelection::warnings() -> Array[String]` | Stable keys: `filename-star-precedence`, `empty-filename`, `contains-path-separator`, `contains-control-character` (each at most once). |

## Filename policy and sanitisation (`filename_policy.mbt`, `filename_sanitize.mbt`)

- `PolicyProfile`: `Portable` / `WindowsLike` / `PosixLike`; `to_string()` →
  `"portable"` / `"windows-like"` / `"posix-like"`.
- `FilenamePolicy` presets: `default()`/`portable()`, `windows_like()`,
  `posix_like()`. Builders: `with_max_length(Int)`, `with_extension(...)`,
  `with_windows_reserved(...)`. Accessors: `profile()`, `max_length()`,
  `extension()`, `windows_reserved()`.
- `ExtensionPolicy::disabled()` / `enabled(allow_list, deny_list)`.
- `WindowsReservedPolicy::enabled()` / `disabled()`.
- `sanitize_filename(name, policy) -> Result[SafeFilenameResult, DispositionError]` —
  errors `FilenamePolicy::UnsafeFilename` only for an empty input.
- `sanitize_portable_filename(name) -> Result[SafeFilenameResult, DispositionError]`
  — the Portable profile.
- `SafeFilenameResult::original() / safe() / changed() / issues()` — issue keys:
  `replaced-path-separator`, `replaced-unsafe-character`, `defused-dot-name`,
  `prefixed-reserved-name`, `trimmed-trailing-char`,
  `truncated-to-max-length`, `denied-extension`,
  `extension-not-in-allow-list` (each at most once).

## Generation (`generator.mbt`)

| Signature | Notes |
| --- | --- |
| `generate_attachment(filename) -> Result[String, DispositionError]` | `attachment; filename="…"; filename*=…` when non-ASCII. |
| `generate_inline(filename) -> Result[String, DispositionError]` | Same, `inline` type. |
| `generate_attachment_with_options / generate_inline_with_options / generate_content_disposition(type, name, options)` | Explicit `GenerateOptions`. |
| `GenerateOptions::default()` | `include_filename_star: true`, no language. |
| `GenerateOptions::with_language(...)`, `without_filename_star()`, `always_filename_star()`, etc. | |

Errors: `QuotedString::InvalidControlCharacter` for CR/LF/NUL/control bytes
(injection defence); `ExtendedValue::InvalidLanguage` for a bad language tag.

## Audit (`audit.mbt`)

| Signature | Notes |
| --- | --- |
| `audit_header(input) -> Result[AuditReport, DispositionError]` | Strict parse + parse diagnostics + model audit in one step. |
| `audit_content_disposition(cd) -> AuditReport` | Model audit; never raises. |
| `audit_disposition_parse(parse) -> AuditReport` | Duplicates + recoveries as issues. |
| `audit_filename(name, policy) -> AuditReport` | Advisory audit of a raw name. |
| `audit_filename_with_media_type(name, media_type, policy) -> AuditReport` | Escalates executable media types. |
| `AuditReport::issues() / issue_count()` | |
| `AuditReport::count_high() / count_at_least_warning()` | |
| `AuditReport::count_severity(sev)` | |
| `AuditIssue::severity() / kind() / parameter() / message()` | |
| `AuditSeverity` | `Info` / `Warning` / `High`; `to_string()` → `"info"`/`"warning"`/`"high"`. Enum variants are read-only from consumer packages; obtain values via `AuditIssue::severity()`. |

`AuditKind` (18) and their stable `to_string()` names:

`missing-filename`, `empty-filename`, `both-filename-and-filename-star`,
`plain-filename-only`, `filename-star-without-fallback`,
`path-separator-in-filename`, `control-character-in-filename`,
`non-ascii-unquoted-filename`, `missing-filename-star-for-non-ascii`,
`unsupported-charset`, `invalid-language-tag`, `duplicate-parameter`,
`recovery-applied`, `extension-risk`, `reserved-windows-name`,
`trailing-dot-or-space`, `long-filename`, `extension-disposition-type`.

## Compatibility bookkeeping (`compatibility.mbt`)

- `compatible_recovery_names() -> Array[String]` — the five stable recovery
  keys: `skip-empty-parameter`, `trailing-semicolon`,
  `empty-parameter-value`, `legacy-unquoted-non-ascii-value`,
  `quoted-extended-value`.
- `ParseCollector` — mutable bookkeeping used by the parser.

## Scanner (`scanner.mbt`)

`Scanner::new(input)`; methods `position()`, `eof()`, `remaining()`,
`total_bytes()`, `peek_byte()`, `peek_at(rel)`, `byte_at(idx)`, `next_byte()`,
`consume_char(b)`, `skip_ows()`, `is_ows()`, `seek(pos)`, `consume_while(fn)`,
`consume_token()`, `consume_value_chars()`, `find_byte(b)`, `take_string()`,
`context_string()`, `context_string_limited(limit)`.

## CLI (`cli.mbt`)

`run_cli(args : Array[String]) -> String` — pure dispatch; returns a JSON
string, never raises. See [cli.md](cli.md).
