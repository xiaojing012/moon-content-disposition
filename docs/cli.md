# `disposition-tool` CLI reference

`disposition-tool` exposes every library concern as a command. It is a thin
executable over the pure `run_cli` function: it reads `@env.args()`, strips the
leading program/runtime path (the argv shape differs per backend — see
[architecture.md](architecture.md)), prints the JSON, and exits `1` when the
result is an error.

## Build and run

```text
moon run cmd/disposition-tool -- help                    # default target (native)
moon run cmd/disposition-tool --target wasm-gc -- parse "attachment; filename=x"
moon run cmd/disposition-tool --target js -- version
# or build an executable once:
moon build cmd/disposition-tool
# then: ./target/.../disposition-tool <command>
```

## Commands

```
parse <value>            serialize <value>          canonicalize <value>
resolve <value>          sanitize <name> [profile]  generate <type> <name>
audit <value>            limits [preset]            profiles
version                  help
```

Command names are case-insensitive (`VERSION` works). Output is always a single
JSON object on stdout with an `"ok"` boolean and a `"command"` field. On an
error the process exits with status 1.

## Output examples

### `parse`

```text
$ moon run cmd/disposition-tool -- parse "attachment; filename=\"report.pdf\"; size=1024"
{"ok":true,"command":"parse","disposition_type":"attachment","parameters":[
 {"name":"filename","value":"report.pdf","form":"token"},
 {"name":"size","value":"1024","form":"token"}]}
```

Extended values render with their decoded value, charset and language:

```text
$ moon run cmd/disposition-tool -- parse "attachment; filename*=UTF-8'en'caf%C3%A9.txt"
{"ok":true,"command":"parse","disposition_type":"attachment","parameters":[
 {"name":"filename*","value":"café.txt","form":"extended","charset":"UTF-8","language":"en"}]}
```

### `serialize` and `canonicalize`

```text
$ moon run cmd/disposition-tool -- serialize "ATTACHMENT; FILE=PDF"
{"ok":true,"command":"serialize","value":"attachment; file=PDF"}

$ moon run cmd/disposition-tool -- canonicalize "attachment; filename*=UTF-8''%E4%B8%AD; filename=fallback.txt"
{"ok":true,"command":"canonicalize","value":"attachment; filename=fallback.txt; filename*=UTF-8''%E4%B8%AD"}
```

### `resolve`

```text
$ moon run cmd/disposition-tool -- resolve "attachment; filename=\"../x\""
{"ok":true,"command":"resolve","filename":"../x","source":"filename","fallback":false,
 "warnings":["contains-path-separator"]}
```

### `sanitize`

```text
$ moon run cmd/disposition-tool -- sanitize "a b.txt"
{"ok":true,"command":"sanitize","original":"a b.txt","safe":"a_b.txt",
 "changed":true,"issues":["replaced-unsafe-character"]}

$ moon run cmd/disposition-tool -- sanitize "CON" "windows-like"
{"ok":true,"command":"sanitize","original":"CON","safe":"_CON",
 "changed":true,"issues":["prefixed-reserved-name"]}
```

Profiles: `portable` (default), `windows-like`, `posix-like`.

### `generate`

```text
$ moon run cmd/disposition-tool -- generate attachment "café.txt"
{"ok":true,"command":"generate","value":"attachment; filename=\"café.txt\"; filename*=UTF-8''caf%C3%A9.txt"}

$ moon run cmd/disposition-tool -- generate attachment "a
b"
{"ok":false,"command":"generate","error":{"stage":"QuotedString","kind":"InvalidControlCharacter",...}}
```

The disposition type must be `attachment` or `inline`.

### `audit`

```text
$ moon run cmd/disposition-tool -- audit "attachment; filename=\"../x\""
{"ok":true,"command":"audit","issues":[
 {"severity":"info","kind":"plain-filename-only","parameter":"filename","message":"only the plain filename parameter is present"},
 {"severity":"high","kind":"path-separator-in-filename","parameter":"filename","message":"filename contains a path separator"}]}
```

### `limits` and `profiles`

```text
$ moon run cmd/disposition-tool -- limits
{"ok":true,"command":"limits","preset":"default","max_input_bytes":1048576,"max_parameters":256,...}

$ moon run cmd/disposition-tool -- limits strict
{"ok":true,"command":"limits","preset":"strict","max_input_bytes":16384,"max_parameters":32,...}

$ moon run cmd/disposition-tool -- profiles
{"ok":true,"command":"profiles","profiles":[{"name":"portable",...},{"name":"windows-like",...},{"name":"posix-like",...}]}
```

### `version` and `help`

```text
$ moon run cmd/disposition-tool -- version
{"ok":true,"command":"version","version":"0.1.0-dev"}

$ moon run cmd/disposition-tool -- help
{"ok":true,"command":"help","commands":["parse","serialize","canonicalize","resolve","sanitize","generate","audit","limits","profiles","version","help"],...}
```

## Errors

Every failure is a structured JSON error object:

```text
$ moon run cmd/disposition-tool -- parse "; filename=x"
{"ok":false,"command":"parse","error":{"stage":"DispositionType","kind":"InvalidDispositionType","offset":0,"context":"expected a disposition type token"}}
```

- `stage` — one of the 13 `DispositionErrorStage` names;
- `kind` — one of the 22 `DispositionErrorKind` names;
- `offset` — UTF-8 byte offset into the input (`0` when not meaningful);
- `context` — a short, bounded excerpt of the input.

`ok:false` implies a non-zero exit status. The command-level error kinds are
`no-command`, `unknown-command`, and `usage` (missing arguments).

## JSON guarantees

- Output is a single JSON object per invocation; no trailing newline beyond
  `println`.
- Values are always JSON-escaped (quotes, backslashes, control characters).
- Everything is deterministic: the same command produces the same JSON.
- No command unwraps or panics; malformed input is a structured error.
