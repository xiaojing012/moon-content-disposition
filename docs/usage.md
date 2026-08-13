# Usage guide

This guide walks through the five operations every Content-Disposition caller
needs, with the recommended code shape. All examples use the library aliased as
`@cd` (the import `"localdev/moon-content-disposition" @cd`).

## 1. Parse a header value

```moonbit
let header = "attachment; filename=\"report.pdf\"; size=1024"

match @cd.parse_content_disposition(header) {
  Err(e) => println("parse failed: \{e.to_display()}") // stage, kind, offset, context
  Ok(cd) => {
    let type = cd.disposition_type().to_lower_name()      // "attachment"
    let params = cd.parameter_count()                      // 2
    for p in cd.parameters() {
      println("\{p.name()} = \{render(p.value())}")
    }
  }
}
```

`render` distinguishes the three value forms:

```moonbit
fn render(v : @cd.ParameterValue) -> String {
  match v.extended() {
    Some(ev) => "\{ev.value()} (extended, charset \{ev.charset()})"
    None => "\{v.plain().unwrap()} (plain)"
  }
}
```

> **Failure modes.** The parser returns a structured `DispositionError`, not a
> message string. Dispatch on `e.kind()` (22 stable kinds) rather than matching
> text. For an input that might be huge, pass tighter `Limits`:
>
> ```moonbit
> let opts = @cd.ParseOptions::new().with_limits(@cd.Limits::strict())
> match @cd.parse_content_disposition_with_options(header, opts) { ... }
> ```

## 2. Resolve the download filename

RFC 6266 §4.3: when both `filename*` and `filename` are present, `filename*`
(the RFC 8187 value, decoded) takes precedence and `filename` is the fallback.

```moonbit
let header = "attachment; filename=fallback.txt; filename*=UTF-8'en'caf%C3%A9.txt"

match @cd.parse_content_disposition(header) {
  Err(e) => ()
  Ok(cd) =>
    match @cd.resolve_filename(cd) {
      Err(e) => println("no usable filename: \{e.to_display()}") // InvalidFilename
      Ok(sel) => {
        let name = sel.selected()        // "café.txt"
        let source = sel.source()        // FilenameStar
        let has_fallback = sel.fallback() // true
        for warning in sel.warnings() {
          println("advisory: \{warning}") // e.g. "filename-star-precedence"
        }
      }
    }
}
```

`resolve_filename` never sanitises. The selected value can still contain path
separators, control characters, or be `.`/`..` — that is the sanitizer's job.

## 3. Sanitise before touching the filesystem

**A value from a header is untrusted input.** Always run the resolved name
through a policy before writing it anywhere.

```moonbit
match @cd.sanitize_portable_filename(name) {
  Err(e) => println("empty input: \{e.to_display()}") // only failure mode
  Ok(result) => {
    let safe = result.safe()   // a single path component
    if result.changed() {
      for issue in result.issues() {
        println("changed: \{issue}")
      }
    }
  }
}
```

Choosing a profile:

- `Portable` (the default) — only `A-Za-z0-9._-` survive; everything else
  becomes `_`. Use for names that may travel between operating systems.
- `WindowsLike` — keeps most code points, forbids `< > : " / \ | ? *` and C0
  controls, defuses reserved names and trailing dots/spaces.
- `PosixLike` — the most permissive: only `/` and NUL are replaced.

```moonbit
let policy = @cd.FilenamePolicy::windows_like().with_max_length(120)
match @cd.sanitize_filename(name, policy) { ... }
```

> **Guarantees.** A non-empty input never fails and never yields an empty name:
> `.` and `..` become `_`, a name made only of dots and spaces falls back to
> `_`. The result contains no `/` or `\`. Sanitising the result of a
> sanitisation is a no-op (idempotent).

## 4. Generate a header from your own filename

When you own the filename (a user upload, a report you generated) and need a
`Content-Disposition` value that preserves it:

```moonbit
match @cd.generate_attachment("café report.pdf") {
  Err(e) => println("control characters rejected: \{e.to_display()}")
  Ok(value) => // "attachment; filename=\"café report.pdf\"; filename*=UTF-8''caf%C3%A9%20report.pdf"
    println(value)
}
```

Behaviour:

- the disposition type is emitted in canonical lowercase;
- `filename="…"` is always emitted as a quoted-string (lossless);
- when the filename contains non-ASCII, an RFC 8187 `filename*=UTF-8'…'…` is
  additionally emitted (the RFC 8187 §5 producer requirement);
- **CR, LF, NUL and other control bytes are rejected** rather than emitted —
  this is the header-injection defence;
- `generate_inline(name)` produces the `inline` form; `generate_*_with_options`
  lets you disable `filename*`, attach a language tag, or always emit `filename*`.

The generated value round-trips: parsing it and resolving the filename returns
exactly the original name.

## 5. Canonicalise and audit

Canonicalisation normalises a value for storage, comparison, or logging:

```moonbit
let canonical = @cd.canonicalize_content_disposition(
  "ATTACHMENT; FILE=fallback.txt; FILE*=UTF-8''caf%C3%A9.pdf",
)
// Ok("attachment; filename=fallback.txt; filename*=UTF-8''caf%C3%A9.pdf")
// (lowercased names; filename emitted before filename*; deterministic encoding)
```

Canonicalisation is idempotent: canonicalising the canonical form returns the
same string.

The audit layer reports RFC 6266 §7 concerns before anything is written:

```moonbit
match @cd.audit_header("attachment; filename=\"../../install.exe\"") {
  Err(e) => println("value does not parse: \{e.to_display()}")
  Ok(report) => {
    if report.count_high() > 0 {
      println("this value is risky; reject or re-name it")
    }
    if report.count_at_least_warning() > 0 {
      println("warnings present; review before saving")
    }
    for issue in report.issues() {
      println("[ \{issue.severity().to_string()} ] \{issue.kind().to_string()}: \{issue.message()}")
    }
  }
}
```

`audit_filename_with_media_type(name, media_type, policy)` strengthens the
extension-risk finding when the declared media type is executable
(`application/octet-stream` + `.exe` → High, `.exe` alone → Warning).

## Putting it together

The recommended server-side flow for a download:

```moonbit
// 1. Parse (with limits), 2. resolve, 3. audit, 4. sanitise.
let policy = @cd.FilenamePolicy::default()
match @cd.parse_content_disposition(header) {
  Err(e) => return Err(e) // log and reject
  Ok(cd) => {
    match @cd.resolve_filename(cd) {
      Err(e) => return Err(e)
      Ok(sel) => {
        let report = @cd.audit_content_disposition(cd)
        // Optional: reject on High severity issues.
        let result = @cd.sanitize_filename(sel.selected(), policy)
        // result.safe() is the only value that reaches the filesystem.
      }
    }
  }
}
```

## Interoperability notes

- **Names are case-insensitive.** Parameter names (`filename`, `FILENAME`,
  `Filename`) are compared case-insensitively per RFC 6266 §4.2; casing is
  preserved in the model and only normalised by serialisation/canonicalisation.
- **Extensions are preserved.** The parser accepts and the model keeps
  `disp-ext-parm` parameters (`size=1024`, `name=field`, …), including
  duplicates in compatible mode. `to_debug_string()` is the quick way to
  eyeball a model in tests and logs.
- **The `form-data` type.** `attachment`, `inline` and any extension token are
  all accepted. `audit_header("form-data; name=x")` flags the extension
  disposition type (informational).
