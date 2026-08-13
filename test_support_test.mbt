// test_support_test.mbt — Deterministic test helpers shared by the whole
// suite. Test-only; never shipped in the library itself.
//
// Every property-style test uses the fixed-seed generator below so that the
// suite is byte-for-byte reproducible on any machine and on all three
// supported targets (wasm-gc, js, native). The generator is the classic
// Park–Miller minimal-standard linear congruential generator (modulus
// 2^31 - 1, multiplier 48271): every intermediate product stays below 2^47,
// so it can never overflow `Int` on any supported target, and `%` by a
// positive divisor never produces a negative value.

///| A deterministic pseudo-random number generator (Park–Miller, computed
///| with Schrage's method).
///
/// The generator is `x -> 48271 * x mod (2^31 - 1)`. Schrage's algorithm
/// evaluates that product using only sub-2^31 intermediate values, so the
/// generator is exactly the same on 32-bit and 64-bit `Int` targets — the
/// whole suite is reproducible on wasm-gc, js and native.
struct Prng {
  mut state : Int
}

///| A generator seeded with `seed`; equal seeds give equal sequences.
fn prng(seed : Int) -> Prng {
  let s = seed % 2147483647
  { state: if s <= 0 { 1 } else { s } }
}

///| The next value in `[1, 2147483646]`.
fn Prng::next_int(self : Prng) -> Int {
  let a = 48271
  let m = 2147483647
  let q = 44488
  let r = 3399
  // m = a * q + r, so a * lo - r * hi stays within [-m, m).
  let hi = self.state / q
  let lo = self.state % q
  let t = a * lo - r * hi
  self.state = if t > 0 { t } else { t + m }
  self.state
}

///| A random integer in `[0, bound)`. `bound` must be positive.
fn Prng::below(self : Prng, bound : Int) -> Int {
  self.next_int() % bound
}

///| A random boolean.
fn Prng::bool(self : Prng) -> Bool {
  self.next_int() % 2 == 0
}

///| The HTTP token alphabet (RFC 7230 `tchar`).
const TOKEN_ALPHABET : String = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&'*+-.^_`|~"

///| Characters that commonly appear in user-facing file names.
const FILE_ALPHABET : String = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ._-()[]{},;=+#%@!&~"

///| Non-ASCII characters used to exercise RFC 8187 and sanitizer paths.
const UNICODE_ALPHABET : String = "你好世界café日本漢字πrésumé—©®中文测试"

///| A random string of `len` code points drawn from `alphabet`.
fn random_string_from(rng : Prng, alphabet : String, len : Int) -> String {
  let chars : Array[Char] = []
  for ch in alphabet {
    chars.push(ch)
  }
  let sb = StringBuilder()
  for i = 0; i < len; i = i + 1 {
    sb.write_char(chars[rng.below(chars.length())])
  }
  sb.to_string()
}

///| A random non-empty HTTP token of length at most `max_len`.
fn random_token(rng : Prng, max_len : Int) -> String {
  let len = 1 + rng.below(max_len)
  random_string_from(rng, TOKEN_ALPHABET, len)
}

///| A random non-empty ASCII file name of length at most `max_len`.
fn random_filename(rng : Prng, max_len : Int) -> String {
  let len = 1 + rng.below(max_len)
  random_string_from(rng, FILE_ALPHABET, len)
}

///| A random non-empty Unicode file name of length at most `max_len`.
fn random_unicode_name(rng : Prng, max_len : Int) -> String {
  let len = 1 + rng.below(max_len)
  random_string_from(rng, UNICODE_ALPHABET, len)
}

// --- assertion helpers ---------------------------------------------------

///| Asserts that `cd` renders exactly as `expected`.
fn expect_cd(cd : ContentDisposition, expected : String) -> Unit raise {
  assert_true(
    cd.to_debug_string() == expected,
    msg="expected CD \{expected}, got \{cd.to_debug_string()}",
  )
}

///| Parses `input` and asserts the resulting model renders as `expected`.
fn expect_parse(input : String, expected : String) -> Unit raise {
  match parse_content_disposition(input) {
    Ok(cd) => expect_cd(cd, expected)
    Err(e) =>
      assert_true(
        false,
        msg="expected parse Ok(\{expected}) for input \{input}, got \{e.to_display()}",
      )
  }
}

///| Parses `input` and asserts it fails with the given stage and kind.
///
/// `stage` and `kind` are the stable `to_string` names, e.g. `"Input"` and
/// `"EmptyInput"`. (Enum values cannot be named in expression position from
/// the blackbox test package, so comparisons go through `to_string`.)
fn expect_parse_error(input : String, stage : String, kind : String) -> Unit raise {
  match parse_content_disposition(input) {
    Ok(cd) =>
      assert_true(
        false,
        msg="expected parse Err(\{stage}/\{kind}) for input \{input}, got \{cd.to_debug_string()}",
      )
    Err(e) =>
      assert_true(
        e.stage().to_string() == stage && e.kind().to_string() == kind,
        msg="input \{input}: expected Err(\{stage}/\{kind}), got Err(\{e.stage().to_string()}/\{e.kind().to_string()})",
      )
  }
}

///| Asserts that the two string arrays are element-wise equal.
fn expect_same_strings(a : Array[String], b : Array[String]) -> Unit raise {
  assert_true(same_strings(a, b), msg="expected \{show_strings(a)}, got \{show_strings(b)}")
}

///| Element-wise equality for `Array[String]` (arrays are not structurally
///| comparable with `==`).
fn same_strings(a : Array[String], b : Array[String]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///| Renders a string array for an assertion message.
fn show_strings(a : Array[String]) -> String {
  let sb = StringBuilder()
  sb.write_string("[")
  for i = 0; i < a.length(); i = i + 1 {
    if i > 0 {
      sb.write_string(", ")
    }
    sb.write_string(a[i])
  }
  sb.write_string("]")
  sb.to_string()
}

///| Whether `key` appears in `issues`.
fn has_key(issues : Array[String], key : String) -> Bool {
  for i in issues {
    if i == key {
      return true
    }
  }
  false
}

///| Parses in compatible mode (duplicates preserved, recoveries applied)
///| and unwraps. Used by tests that deliberately exercise duplicate
///| parameters, which strict mode rejects.
fn parse_compatible(input : String) -> ContentDisposition {
  match parse_content_disposition_with_options(input, ParseOptions::compatible()) {
    Ok(cd) => cd
    Err(e) => abort("compatible parse failed for \{input}: \{e.to_display()}")
  }
}
