# Strict vs. compatible parsing

RFC 6266 and RFC 8187 define the grammar, but real-world servers send headers
that step outside it: trailing semicolons, empty parameters, unquoted non-ASCII
values, quoted `filename*`. `ParseMode` decides how this library treats those
deviations.

## The two modes

- **`Strict`** (default) follows the project-defined RFC 6266 / RFC 8187 scope
  with no leniency. Anything outside the grammar is an error with a structured
  `DispositionError`.
- **`Compatible`** additionally accepts a small, individually documented set of
  real-world behaviours. Every compatible recovery actually applied is recorded
  in the parse result (`DispositionParse::recoveries`) and surfaces as a
  `RecoveryApplied` audit issue, so no deviation is silent.

```moonbit
let opts = @cd.ParseOptions::compatible()
let detailed = @cd.parse_content_disposition_detailed(header, opts)
// recoveries() lists exactly which leniencies were needed for THIS input
```

**Compatible mode never relaxes security-critical validation.** Control
characters are rejected, percent-encoding is validated, charsets are validated,
and the input/parameter limits still apply — in both modes.

## The five compatible recoveries

`compatible_recovery_names()` returns these stable keys (documentation order):

| Key | What is accepted | Why | Risk |
| --- | --- | --- | --- |
| `skip-empty-parameter` | `;;` (an empty parameter element) is skipped | `attachment;;size=1` appears in the wild | Low; ambiguous but harmless |
| `trailing-semicolon` | A trailing `;` with no parameter is ignored | `attachment;` is common from sloppy generators | Low |
| `empty-parameter-value` | `name=` with an empty value | Some frameworks emit this | Low; value is the empty string |
| `legacy-unquoted-non-ascii-value` | An unquoted value containing obs-text bytes (e.g. `filename=café.txt`) | Pre-RFC 6266 headers | Medium; the bytes are kept as-is, sanitize before use |
| `quoted-extended-value` | An RFC 8187 extended value written with surrounding quotes | Broken generators | Low; the quotes are stripped |

Each key appears at most once per parse. In strict mode the same inputs are
errors:

| Input | Strict behaviour |
| --- | --- |
| `attachment;;size=1` | `ParameterName::ExpectedToken` |
| `attachment;` | `ParameterName::ExpectedToken` (parameter expected after `;`) |
| `attachment; name=` | `ParameterValue::MissingParameterValue` |
| `attachment; filename=café.txt` | `Input::TrailingInput` (the obs-text byte terminates the token; the rest of the value is trailing input) |
| `attachment; filename*="UTF-8''a"` | `ExtendedValue::InvalidExtendedValue` (quotes are not part of ext-value) |

## Duplicate parameters

RFC 6266 leaves duplicate parameter names undefined. This library decides:

- **Strict**: a duplicate parameter name is an error
  (`ParameterName::DuplicateParameter`), because accepting the second value
  would be guessing.
- **Compatible**: duplicates are preserved in input order in the model and each
  duplicate name is recorded in `DispositionParse::duplicates()`; the audit
  layer reports a `DuplicateParameter` warning.

The typed accessors are affected: `filename()` / `filename_star()` /
`get_parameter()` return the **last** plain/extended value and the **first**
occurrence respectively, matching the "later parameter wins for typed lookup"
convention. The ordered `parameters()` array is authoritative for round-trips.

## obs-text and non-ASCII values

RFC 6266 restricts `filename` values to ASCII in the strict reading of the
grammar, but the installed base sends obs-text (bytes ≥ 0x80) and UTF-8. The
parser:

- accepts obs-text **only inside quoted strings** (matching RFC 7230 field
  values in practice);
- rejects raw obs-text in an unquoted token value in strict mode, and records
  `legacy-unquoted-non-ascii-value` in compatible mode;
- keeps the bytes in the model so `serialize_content_disposition` round-trips
  them, while `audit_*` flags `non-ascii-unquoted-filename` and
  `missing-filename-star-for-non-ascii`.

The honest recommendation, and what `generate_*` implements: **a non-ASCII
filename is carried by `filename*` (RFC 8187), with a quoted `filename` acting
as the fallback.**

## OWS around separators

SP and HTAB are accepted around `;` and `=` (RFC 7230 field-value conventions)
in both modes. CR and LF are never whitespace. This is a strict-grammar
convenience, not a compatible-mode deviation, and is reflected by the grammar in
[architecture.md](architecture.md).

## What is never relaxed

- control-character rejection (CR/LF/NUL injection defence);
- percent-encoding validity (a `%` must be followed by two hex digits);
- charset validation (`UTF-8` / `ISO-8859-1` only);
- all `Limits`.

## Recoveries and the audit

`audit_header` runs a strict parse and combines the parse diagnostics with the
model audit. For a header that needs leniency, call the detailed API and feed
the result to `audit_disposition_parse`:

```moonbit
let opts = @cd.ParseOptions::compatible()
match @cd.parse_content_disposition_detailed(header, opts) {
  Err(e) => ()
  Ok(p) => {
    let report = @cd.audit_disposition_parse(p) // duplicates + recoveries
    for issue in report.issues() {
      println(issue.message())
    }
  }
}
```
