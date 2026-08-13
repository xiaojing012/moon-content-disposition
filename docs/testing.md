# Testing

The test suite is the proof that the parser, serializer, resolver, sanitizer
and auditor behave. **327 tests across 25 files pass on all three targets**
(`native`, `js`, `wasm-gc`) with a deterministic, seeded PRNG — the same suite
reproduces exactly on every run and every platform.

## Running

```text
moon test                 # native (default)
moon test --target js
moon test --target wasm-gc
scripts/verify_all.ps1    # end-to-end verification of everything (see below)
```

`moon test` runs the blackbox test package: it can see every public symbol of
the library but nothing private, and enum variants are read-only, so the tests
exercise the library exactly the way a consumer would.

## Layout

| File | Covers |
| --- | --- |
| `model_test.mbt` | the data model: accessors, typed lookups, semantic equality, debug rendering |
| `parser_test.mbt` | the RFC 6266 §4.2 grammar, OWS, `;`/`=` handling, parameters, duplicates |
| `scanner_test.mbt` | the byte scanner: position, peeks, token/value consumption, OWS, context windows |
| `token_test.mbt` | the RFC 7230 byte tables: tchar, qdtext, quoted-pair, control, obs-text, hex |
| `quoted_string_test.mbt` | quoted-string parsing/serialising, escaping, empty strings |
| `parameter_test.mbt` | one parameter: name/value forms, extended names |
| `rfc8187_test.mbt` | RFC 8187 ext-value parsing/serialising, charsets, language tags, limits |
| `percent_codec_test.mbt` | percent-encoding/decoding, strict `%HH` validation |
| `charset_test.mbt` | UTF-8 / ISO-8859-1 encode/decode, canonical casing, `fits_iso8859_1` |
| `serializer_test.mbt` | deterministic serialisation, preserve-case round-trips, token validity |
| `canonicalize_test.mbt` | canonical form, `filename`-before-`filename*` ordering, idempotence |
| `filename_policy_test.mbt` | the three profiles, extension policy, reserved-name policy |
| `filename_sanitize_test.mbt` | sanitisation invariants, per-profile character rules, issue keys |
| `resolver_test.mbt` | RFC 6266 §4.3 precedence, fallback, warnings, error cases |
| `generator_test.mbt` | generate/parse round-trips, non-ASCII handling, CR/LF rejection |
| `audit_test.mbt` | every audit kind, severities, severity counts, media-type escalation |
| `limits_test.mbt` | the three `Limits` presets and their accessors |
| `invalid_input_test.mbt` | malformed inputs: every error stage/kind is reached |
| `security_test.mbt` | the security invariants: injection, traversal, reserved names |
| `truncation_test.mbt` | bounded contexts, over-limit rejection, no silent truncation |
| `roundtrip_test.mbt` | parse → serialise round-trips across many forms |
| `rfc_examples_test.mbt` | the worked examples from RFC 6266 §5 and RFC 8187 §5 |
| `cli_test.mbt` | the `disposition-tool` command surface (pure JSON) |
| `property_test.mbt` | deterministic PRNG property cases (see below) |
| `test_support_test.mbt` | shared helpers: seeded PRNG, random alphabets, assertion helpers |

## Deterministic property testing

The property suite (`property_test.mbt`, `filename_sanitize_test.mbt`,
`canonicalize_test.mbt`) uses a small seeded LCG PRNG, so the exact same case
sequence runs every time:

- **2600+ property cases** in `property_test.mbt`: PRNG determinism, token
  validity, parameter-count consistency, generate→parse→resolve round-trips
  for ASCII and Unicode filenames, corpus determinism;
- **1300 sanitizer invariants** across all three profiles with random policies:
  the safe name contains no separators, is never empty/dot-only, and
  sanitising the safe name is a no-op;
- **600 canonicalisation cases**: `canonicalize(canonicalize(x)) ==
  canonicalize(x)` and form-stability across equivalent wire forms.

The assertions use `assert_true(cond, msg=…)` so a failure names the failing
input, and the PRNG seeds are fixed in source so a failure reproduces forever.

## Blackbox constraints the tests honour

- Enum variants are read-only: the tests obtain enum values through library
  accessors (e.g. `ParseOptions::strict().mode()`, `issue.severity()`) and
  compare via `to_string()` names.
- `Error` is abstract: the tests never catch; they use the `Result` API.
- Bare-number method calls (e.g. `255.to_string()`) are avoided.

## What the suite proves (checksums of behaviour)

1. **Losslessness**: a parsed value re-serialises deterministically; the
   preserve-case serializer reproduces the original wire token and casing.
2. **Precedence**: `filename*` wins over `filename`; fallback is reported.
3. **Idempotence**: canonicalisation and sanitisation are stable under
   repetition.
4. **Bounds**: every limit is an error, never a silent truncation; error
   contexts never echo a large input.
5. **Injection defence**: control bytes never round-trip through the
   generator; CR/LF never become whitespace in the parser.
6. **No panic paths**: the CLI and all examples have no `unwrap`; every
   `Result` is rendered (success or structured error).

## Coverage targets

| Target | Value |
| --- | --- |
| Named tests | 327 (target 100–150) |
| Test files | 25 (target 18+) |
| Deterministic property cases | 2600+ (target ≥ 1000) |
| Sanitizer invariants | 1300 (target ≥ 1000) |
| Canonicalisation cases | 600 (target ≥ 500) |
| Targets green | native, js, wasm-gc (3/3) |
