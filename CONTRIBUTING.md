# Contributing

Thank you for considering contributing to `moon-content-disposition`. This
project is currently a **local development build**: it is not published, and
final ownership and publishing decisions are deferred. Until those are made,
contributions are welcome as local work, code review, and tests; please do not
open pull requests against a remote you do not control, and do not publish the
package.

## Ground rules

- **No personal information.** Do not add real names, email addresses, school
  or organisational affiliations, or personal GitHub/Mooncakes handles to the
  code or docs.
- **No fabricated links.** Never add a repository or homepage URL that does not
  exist. If a URL is not real, omit it.
- **No false claims.** Do not write "100% RFC compliant". Say precisely what is
  implemented and what is decided differently (see `docs/compatibility.md`).
- **Keep the version in one place.** The version string lives only in
  `library_version()` in `model.mbt`; `moon.mod` mirrors it. Change both
  together and nowhere else.

## Development workflow

### Build and test

```text
moon build                                    # library
moon test                                     # native
moon test --target js
moon test --target wasm-gc
moon run cmd/disposition-tool -- help         # CLI smoke test
moon run examples/parse                       # example smoke test
```

Before finishing any change, run `scripts/verify_all.ps1`, which exercises all
three targets plus the CLI and examples and reports a summary.

### Code style

- Follow the surrounding style: two-space indent, `///|` doc comments on every
  public symbol, `//` comments explaining *why*.
- Every public function returns `Result[T, DispositionError]` — it must never
  raise and never unwrap at a boundary. Internal functions may `raise`; convert
  at the boundary with `unwrap_or_raise` / `unwrap_disposition_error`.
- New behaviour needs tests. Keep the suite deterministic: use the seeded PRNG
  helpers in `test_support_test.mbt`, never `Math.random()` or wall-clock time.
- The blackbox test package cannot construct enum variants or catch `Error`;
  design assertions around library accessors and `to_string()` names.

### What a good change looks like

1. A failing test that names the behaviour.
2. The minimal implementation change.
3. The test passing on all three targets.
4. Docs updated (`docs/`) if the public surface changed, and the CHANGELOG if
   behaviour changed.

## Test conventions

- Named tests live in `*_test.mbt` in the package root; 25 files cover one
  concern each (see `docs/testing.md`).
- Property tests use the fixed-seed PRNG so every run reproduces exactly.
- Assertion helpers (`expect_parse`, `expect_cd`, `expect_same_strings`,
  `inspect`, `assert_true`) live in `test_support_test.mbt`; reuse them instead
  of inventing new ones.

## License

By contributing you agree that your contributions are licensed under the
project's Apache-2.0 license (see `LICENSE`).
