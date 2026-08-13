# International filenames (RFC 8187)

A plain `filename` parameter can only carry ASCII and obs-text bytes. For real
international names, HTTP uses the RFC 8187 `ext-value` form behind the
`filename*` parameter:

```
filename* = charset "'" [ language "'" ] value-chars

    filename*=UTF-8'en'caf%C3%A9.txt
              └─┴ └─┴ └────────────┴───
              UTF-8  en  percent-encoded value
```

The syntax is `charset "'" [ language "'" ] value-chars`, where `value-chars` is
the `attr-char` / `pct-encoded` set. This library implements that grammar for
the two charsets that matter in practice — **UTF-8** and **ISO-8859-1** — with
strict validation at every step.

## Parsing `filename*`

`parse_extended_value` accepts the full RFC 8187 form and returns a decoded
`ExtendedValue { charset, language, value }`:

| Piece | Rule enforced |
| --- | --- |
| `charset` | Must be `UTF-8` or `ISO-8859-1` (case-insensitive); anything else is `Charset::UnsupportedCharset`. Stored in canonical casing (`UTF-8`, `ISO-8859-1`). |
| `language` | Optional. When present, must match the RFC 5646 `language-tag` shape (alpha subtags, digits subtags, private-use `x-`/`X-` primary subtags). A malformed tag is `ExtendedValue::InvalidLanguage`. |
| `value-chars` | Each `%HH` must be two hex digits (`PercentEncoding::InvalidPercentEncoding` otherwise). After percent-decoding, the byte sequence must be valid for the declared charset: UTF-8 must be well-formed (`PercentEncoding::InvalidUtf8` / `Charset::InvalidUtf8`), ISO-8859-1 must fit (`Charset::InvalidIso8859`... a non-decodable byte is rejected). |
| quoting | An `ext-value` must NOT be wrapped in quotes; `filename*="UTF-8''a"` is `ExtendedValue::InvalidExtendedValue` (strict) or the `quoted-extended-value` recovery (compatible). |

> The ext-value byte bound (`max_extended_value_bytes`) applies to the *value*
> bytes (after the second apostrophe), not the charset/language prefix.

## Serialising `filename*`

`serialize_extended_value` re-encodes deterministically:

- the charset is emitted in canonical casing;
- the language tag is emitted if present;
- every value byte is percent-encoded with **uppercase hex** (`%C3%A9`, never
  `%c3%a9`), reserving only the `attr-char` set unescaped.

Deterministic encoding is what makes canonicalisation idempotent and
round-trip serialisation byte-stable.

## Charset handling

`charset.mbt` exposes the codec boundary:

- `is_supported_charset(charset)` — `UTF-8` / `ISO-8859-1` (case-insensitive);
- `canonical_charset(charset)` — the canonical casing, or `None`;
- `decode_bytes(charset, bytes)` — bytes → String (validated);
- `encode_to_bytes(charset, value)` — String → bytes (validated);
- `fits_iso8859_1(value)` — true when every code point is U+0000–U+00FF.

The parser uses these so that `UTF-8''%E4%B8%AD` decodes to `中`, and
`ISO-8859-1''caf%E9` decodes to `café` (U+00E9), each through the correct
codec.

## Language tags

RFC 8187 allows an optional RFC 5646 language tag. `valid_language_tag`
enforces the shape without resolving IANA registrations: alpha subtags,
optional numeric subtags, and private-use `x-…`/`X-…` primary subtags are
accepted; empty tags, embedded spaces, and malformed subtag lengths are
rejected. The tag is stored and re-emitted verbatim.

## Filename precedence (RFC 6266 §4.3)

When both `filename` and `filename*` are present, the RFC 8187 value **wins**:

```
attachment; filename=fallback.txt; filename*=UTF-8'en'caf%C3%A9.txt
                                   └────────────────┬────────────────┘
                                              selected by resolve_filename
```

`resolve_filename` returns:

- `selected` — the decoded `filename*` value (`café.txt`);
- `source` — `FilenameStar`;
- `fallback` — `true` (the plain `filename` was present);
- `warnings` — `filename-star-precedence` when both were present.

If `filename*` is absent or the value is unusable, the plain `filename` is
selected instead. `resolve_filename` does **not** sanitise: the decoded value
may still contain path separators or control bytes, and the audit layer
(`audit_content_disposition`) will say so.

## Producing international values

The generator follows the RFC 8187 §5 producer requirement:

- a pure-ASCII filename produces only `filename="…"`;
- a filename with non-ASCII produces both `filename="…"` (quoted, obs-text
  fallback) **and** `filename*=UTF-8''<encoded>` (the unambiguous form);
- CR/LF/NUL/control bytes are rejected outright (injection defence);
- `generate_*_with_options` lets you force `filename*` even for ASCII
  (`always_filename_star`), attach a language tag, or suppress `filename*`
  entirely.

There is deliberately **no transliteration**: `café` stays `café`, never
`cafe`. When ASCII fallback beyond quoting is required, that is an application
policy decision, not something the library guesses.

## Audit checks for international values

`audit.mbt` reports the internationalisation-related concerns:

- `non-ascii-unquoted-filename` (Warning) — a plain `filename` carrying raw
  obs-text/UTF-8 bytes;
- `missing-filename-star-for-non-ascii` (Warning) — non-ASCII without an RFC
  8187 companion;
- `both-filename-and-filename-star` (Info) — both present;
- `plain-filename-only` (Info) — no RFC 8187 companion at all;
- `filename-star-without-fallback` (Info) — `filename*` with no plain fallback;
- `invalid-language-tag` (Warning) / `unsupported-charset` (High) — surfaced
  through the raw extended-value audit path (both are parse errors through
  `audit_header`, since a bad charset or language never parses).

## Worked example

```moonbit
let header = "attachment; filename=\"café.txt\"; filename*=UTF-8'en'caf%C3%A9.txt"

match @cd.parse_content_disposition(header) {
  Err(e) => ()
  Ok(cd) => {
    match @cd.resolve_filename(cd) {
      Ok(sel) => {
        println(sel.selected())           // café.txt
        // sel.source() is FilenameStar; match it to render "filename*".
        // then: sanitize_portable_filename(sel.selected())
      }
      Err(e) => ()
    }
  }
}
```
