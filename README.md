# moon-content-disposition

[![GitHub repository](https://img.shields.io/badge/GitHub-xiaojing012%2Fmoon--content--disposition-181717?logo=github)](https://github.com/xiaojing012/moon-content-disposition)

An RFC 6266 Content-Disposition parser, serializer, international filename
resolver, safe filename policy and security audit toolkit for
[MoonBit](https://www.moonbitlang.com).

The library reads and writes `Content-Disposition` header field values —
`attachment; filename="report.pdf"`, the RFC 8187 internationalised form
`filename*=UTF-8'en'caf%C3%A9.txt`, and the extension parameters used by
`multipart/form-data` (`form-data; name="field"`) — with a structured error
model, bounded resource limits, and an audit layer that surfaces the RFC 6266
Section 7 security concerns before a filename ever reaches a filesystem.

## Highlights

- **Strict, deterministic parser.** Implements the RFC 6266 Section 4.2
  grammar with a stable, structured error model: every failure is a
  `DispositionError` carrying a processing stage, a concrete kind, a UTF-8
  byte offset and a bounded context excerpt.
- **RFC 8187 international filenames.** `filename*` extended values are parsed
  and serialised for the two charsets that matter in practice (`UTF-8` and
  `ISO-8859-1`), with strict percent-decoding, RFC 5646 language tags, and the
  RFC 6266 Section 4.3 precedence rule (`filename*` wins; `filename` is the
  fallback).
- **Safe filename policy.** `resolve_filename` selects the download name;
  `sanitize_filename` turns it into a single safe path component under one of
  three profiles (Portable / Windows-like / Posix-like). Every transformation
  is recorded as a stable issue key; a non-empty name never fails.
- **Security audit.** `audit_header` reports path separators, control
  characters, missing `filename*`, risky extensions, Windows reserved names,
  trailing dots, duplicate parameters and more — each with a severity, before
  anything is written to disk.
- **Deterministic serialisation.** Parsed values re-serialise byte-stably;
  `canonicalize_content_disposition` produces a canonical form that is
  idempotent.
- **CR/LF injection defence.** The generator rejects CR, LF, NUL and other
  control bytes outright rather than emitting them.
- **Bounded resource use.** Seven independent `Limits` (input bytes, parameter
  count, value bytes, …) guarantee that no parse can exhaust memory, loop
  forever, or silently truncate.
- **Portable.** The same code builds and passes 327 tests on the `native`,
  `js` and `wasm-gc` targets. Includes a JSON-emitting CLI (`disposition-tool`)
  and six runnable examples.

## Quick start

```moonbit
let header = "attachment; filename=\"café.txt\"; filename*=UTF-8'en'caf%C3%A9.txt"

match @cd.parse_content_disposition(header) {
  Err(e) => println("parse failed: \{e.to_display()}")
  Ok(cd) => {
    match @cd.resolve_filename(cd) {
      Err(e) => println("resolve failed: \{e.to_display()}")
      Ok(sel) => {
        // sel.selected() == "café.txt", sel.source() == FilenameStar
        match @cd.sanitize_portable_filename(sel.selected()) {
          Err(e) => println("sanitize failed: \{e.to_display()}")
          Ok(result) => println("safe download name: \{result.safe()}")
        }
      }
    }
  }
}
```

Generate a header from a filename of your own:

```moonbit
let value = @cd.generate_attachment("café report.pdf")
// "attachment; filename=\"café report.pdf\"; filename*=UTF-8''caf%C3%A9%20report.pdf"
```

Canonicalise and audit:

```moonbit
let canonical = @cd.canonicalize_content_disposition(
  "ATTACHMENT; FILE=fallback.txt; FILE*=UTF-8''caf%C3%A9.pdf",
)
// "attachment; filename=fallback.txt; filename*=UTF-8''caf%C3%A9.pdf"

match @cd.audit_header("attachment; filename=\"../../install.exe\"") {
  Err(e) => println("audit failed: \{e.to_display()}")
  Ok(report) =>
    for issue in report.issues() {
      println("[ \{issue.severity().to_string()} ] \{issue.kind().to_string()}: \{issue.message()}")
    }
}
```

## The pipeline

Content-Disposition processing in this library is a pipeline; each stage is a
pure function and the output of one is the input of the next.

```
parse → resolve → sanitize
  │         │        └─ FilenamePolicy (Portable / WindowsLike / PosixLike)
  │         └─ RFC 6266 §4.3 precedence, advisory warnings
  └─ ContentDisposition model
       ├─ serialize / canonicalize
       ├─ generate (the inverse of parse)
       └─ audit (advisory, never mutates)
```

The one rule to remember: **a value from a header is untrusted input**. Parse it
with limits, resolve the filename, run it through a sanitisation policy, and
audit it before you write it anywhere.

## Documentation

- [API reference](docs/api.md)
- [Usage guide](docs/usage.md)
- [CLI reference](docs/cli.md)
- [Security model](docs/security.md)
- [Strict vs. compatible parsing](docs/compatibility.md)
- [International filenames (RFC 8187)](docs/internationalization.md)
- [Testing](docs/testing.md)
- [Architecture and design](docs/architecture.md)

## Command-line toolkit

`moon run cmd/disposition-tool -- help` (or `disposition-tool` once built)
prints the eleven commands:

```
parse <value>            serialize <value>          canonicalize <value>
resolve <value>          sanitize <name> [profile]  generate <type> <name>
audit <value>            limits [preset]            profiles
version                  help
```

Every command emits a single JSON object on stdout and exits `1` on a failed
command. See [docs/cli.md](docs/cli.md).

## Examples

Six runnable demonstrations, one per library concern:

```
moon run examples/parse
moon run examples/resolve -- "attachment; filename=fallback.txt; filename*=UTF-8'en'caf%C3%A9.txt"
moon run examples/sanitize
moon run examples/generate -- "café report.pdf"
moon run examples/canonicalize
moon run examples/audit
```

## Building and testing

```text
moon build                     # library
moon build cmd/disposition-tool --target wasm-gc
moon test                      # native (default)
moon test --target js
moon test --target wasm-gc
scripts/verify_all.ps1         # end-to-end verification (three targets)
scripts/count_code.py          # source-line report
```

327 tests across 25 files pass on all three targets, including a fully
deterministic PRNG-driven property suite (2600+ property cases, 1300 sanitizer
invariants, 600 canonicalisation cases). See [docs/testing.md](docs/testing.md).

## Requirements

- MoonBit toolchain `0.1.20260713` or newer. The build is verified on the
  `native`, `js` and `wasm-gc` targets.
- Python 3 for `scripts/count_code.py`; Windows PowerShell for
  `scripts/verify_all.ps1` (the script also works under `pwsh` on other
  platforms).

## Versioning

The single source of truth for the version is `library_version()` in
[model.mbt](model.mbt); `moon.mod` mirrors it. Current version: **0.1.0**.

## License

Apache-2.0. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES).
