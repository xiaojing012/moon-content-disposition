# Architecture

`moon-content-disposition` is a single library package (`localdev/moon-content-disposition`)
plus two thin consumers: the `disposition-tool` command-line executable and six
runnable examples. All parsing, serialisation, resolution and auditing logic
lives in the library so that every byte of behaviour is unit-testable from the
blackbox test package.

## Module layout

```
moon-content-disposition/
├── moon.mod                  module metadata (name, version, license)
├── moon.pkg                  library package manifest
│   ├── model.mbt             data model: DispositionType, ParameterValue,
│   │                         ExtendedValue, DispositionParameter, ContentDisposition
│   ├── parser.mbt            RFC 6266 §4.2 grammar; strict/compatible; duplicates
│   ├── scanner.mbt           byte-level scanner with bounded context excerpts
│   ├── options.mbt           ParseOptions: ParseMode (Strict/Compatible) + Limits
│   ├── limits.mbt            Limits: 7 independent resource bounds + 3 presets
│   ├── error.mbt             DispositionError suberror: stage/kind/offset/context
│   ├── token.mbt             RFC 7230 tchar/qdtext/quoted-pair/OWS byte tables
│   ├── quoted_string.mbt     quoted-string parser and serializer
│   ├── parameter.mbt         one disposition parameter (name=value)
│   ├── rfc8187.mbt           RFC 8187 ext-value parsing/serialisation, language tags
│   ├── percent_codec.mbt     strict percent-encoding/decoding
│   ├── charset.mbt           UTF-8 and ISO-8859-1 encode/decode helpers
│   ├── compatibility.mbt     compatible-mode recovery bookkeeping
│   ├── serializer.mbt        deterministic serialisation + canonicalisation
│   ├── filename_resolver.mbt RFC 6266 §4.3 filename selection + warnings
│   ├── filename_policy.mbt   FilenamePolicy: 3 profiles + extension/reserved rules
│   ├── filename_sanitize.mbt policy-driven sanitisation (SafeFilenameResult)
│   ├── generator.mbt         building header values from a filename
│   ├── audit.mbt             advisory security audit (AuditReport / AuditIssue)
│   └── cli.mbt               pure command-line dispatch (JSON strings)
├── cmd/disposition-tool/     executable: @env.args() + exit codes + println
├── examples/                 parse, resolve, sanitize, generate, canonicalize, audit
├── docs/                     this documentation set
└── scripts/                  verify_all.ps1, count_code.py
```

## Data flow

### Parse

```
input string
  → utf8.encode + max_input_bytes check
  → Scanner (UTF-8 byte cursor, OWS skipping)
  → disposition-type token        (typed into DispositionType, raw kept)
  → while ';' present: parse one disposition parameter
      → name token, optional OWS, '=', value (token / quoted-string / ext-value)
  → duplicate check (strict rejects, compatible records)
  → limit checks (max_parameters, per-name/value byte bounds)
  → ContentDisposition { disposition_type, parameters, raw_disposition_type }
```

The scanner works on UTF-8 bytes with code-point-aware slicing; quoted strings
are decoded with obs-text bytes accepted only inside the quoted form (matching
RFC 7230 field-value reality). Extended values (`name*`) are fully decoded:
charset validated against `UTF-8`/`ISO-8859-1`, percent sequences validated and
decoded, language tags checked against RFC 5646 shape.

### Serialise / canonicalise

`serialize_content_disposition` re-emits a parsed model deterministically:
disposition type and parameter names in canonical lowercase, parameters in
model order, values re-encoded (quoted strings escaped, extended values
percent-encoded with uppercase hex). `canonicalize_content_disposition` parses
then re-serialises with one additional rule — the plain `filename` fallback is
emitted before `filename*`. Canonicalisation is idempotent by construction:
the canonical form re-parses to a model that re-serialises to itself.

### Resolve → sanitize → audit

- `resolve_filename(cd)` applies RFC 6266 §4.3: `filename*` (decoded) wins over
  `filename`; the plain value is kept as a fallback. It reports advisory
  warnings (path separators, control characters, empty name) but does not
  modify the value.
- `sanitize_filename(name, policy)` applies a `FilenamePolicy`: per-profile
  character rules, whole-name `.`/`..` defusing, Windows reserved-name
  defusing, trailing dot/space trimming, length truncation. The result is a
  single path component; a non-empty input never fails. Every change is
  recorded as a stable issue key.
- `audit_*` never mutates anything: it inspects a parsed model (or a raw
  filename) and produces a severity-tagged `AuditReport`.

## Design decisions

1. **Everything returns `Result[T, DispositionError]`, never raises, never
   unwraps at public boundaries.** Internals use `raise` and a small
   `unwrap_or_raise` helper; each public function catches and converts. This is
   what keeps the CLI and the examples free of `unwrap`.

2. **The model preserves information.** Parameter names keep their original
   casing until serialisation, `Token`/`Quoted` forms are kept distinct, the
   raw disposition-type token is remembered for preserve-case round-tripping,
   and duplicate parameters are kept in compatible mode. Lossless parse is what
   makes byte-stable serialisation possible.

3. **Limits are explicit, not magic.** A header can legitimately be megabytes
   long; the parser bounds input bytes, parameter count, name bytes, value
   bytes, extended-value bytes and filename bytes independently, and error
   contexts are truncated to `max_context_bytes`. Over-limit is an error, never
   a silent truncation.

4. **Sanitisation is policy-driven and advisory-audited.** There is no single
   "correct" safe filename; there are three documented profiles. The sanitizer
   is corrective (it changes the name), the auditor is advisory (it reports).
   Neither performs transliteration: a non-portable character becomes `_`, it is
   never "sounded out" into ASCII.

5. **Compatible-mode leniency is recorded, never silent.** The five compatible
   recoveries each surface as a stable key in the parse result and as a
   `RecoveryApplied` audit issue. Compatible mode never relaxes
   security-critical validation (control characters, percent encoding,
   charsets).

6. **Determinism is a tested property.** The PRNG used by the property suite is
   seeded and stable, so `moon test` is reproducible across runs and platforms.

## Consumers

- **`cmd/disposition-tool`** is a thin wrapper: it reads `@env.args()`, strips
  the leading program/runtime path, calls the pure `run_cli`, prints the JSON,
  and exits non-zero when the JSON says `ok:false`. The argv shape differs per
  backend (`[program, …]` on native/wasm-gc, `[node, program.js, …]` on js);
  `strip_program_name` normalises it.
- **`examples/*`** are one-concern demonstrations that strip the program path
  the same way and print human-readable output.

## Targets

The same source compiles to the `native`, `js` and `wasm-gc` targets. The only
target-specific code is the exit-code plumbing in `cmd/disposition-tool`
(`cli_exit_wasm.mbt`, `cli_exit_js.mbt`, `cli_exit_native.mbt`); everything else
is pure MoonBit.
