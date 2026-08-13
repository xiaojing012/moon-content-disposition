// roundtrip_test.mbt — 1000+ deterministic property cases over the whole
// pipeline: parse → serialise → parse, and parse → canonicalise → parse.

test "parse-serialise-parse preserves semantics (1200 cases)" {
  let rng = prng(1001)
  let failures : Array[String] = []
  let mut cases = 0
  for _i = 0; _i < 1200; _i = _i + 1 {
    let input = make_random_cd(rng)
    match parse_content_disposition(input) {
      Ok(cd) => {
        cases = cases + 1
        match serialize_content_disposition(cd) {
          Ok(header) => {
            match parse_content_disposition(header) {
              Ok(again) =>
                if !again.semantic_equal(cd) {
                  failures.push("semantic mismatch: \{input} -> \{header}")
                }
              Err(e) => failures.push("re-parse failed for \{header}: \{e.to_display()}")
            }
          }
          Err(e) => failures.push("serialise failed for \{input}: \{e.to_display()}")
        }
      }
      Err(_) => ()
    }
  }
  assert_true(cases >= 1000, msg="only \{cases} cases ran; the sweep should exceed 1000")
  assert_true(failures.length() == 0, msg="failures: \{show_strings(failures)}")
}

test "parse-canonicalise-parse preserves semantics (1200 cases)" {
  let rng = prng(1002)
  let failures : Array[String] = []
  let mut cases = 0
  for _i = 0; _i < 1200; _i = _i + 1 {
    let input = make_random_cd(rng)
    match parse_content_disposition(input) {
      Ok(cd) => {
        cases = cases + 1
        match canonicalize_content_disposition(input) {
          Ok(header) => {
            match parse_content_disposition(header) {
              Ok(again) =>
                if !again.semantic_equal(cd) {
                  failures.push("semantic mismatch: \{input} -> \{header}")
                }
              Err(e) => failures.push("re-parse failed for \{header}: \{e.to_display()}")
            }
          }
          Err(e) => failures.push("canonicalise failed for \{input}: \{e.to_display()}")
        }
      }
      Err(_) => ()
    }
  }
  assert_true(cases >= 1000, msg="only \{cases} cases ran; the sweep should exceed 1000")
  assert_true(failures.length() == 0, msg="failures: \{show_strings(failures)}")
}

test "the canonical form is independent of casing and whitespace" {
  // The Token/Quoted distinction is preserved by the serializer, so the
  // wire-form independence property holds across casing and OWS, not across
  // quoting. Different casings and whitespace layouts canonicalise to one
  // string.
  let base = "attachment; filename=report.pdf; size=42"
  let variants = [
    "attachment; filename=report.pdf; size=42",
    "ATTACHMENT; FILENAME=report.pdf; SIZE=42",
    "Attachment ; Filename = report.pdf ; size = 42",
    "  attachment  ;  filename = report.pdf  ; size = 42 ",
  ]
  match canonicalize_content_disposition(base) {
    Ok(canon) =>
      for variant in variants {
        match canonicalize_content_disposition(variant) {
          Ok(c) => inspect(c, content=canon)
          Err(e) => assert_true(false, msg="canonicalise failed for \{variant}: \{e.to_display()}")
        }
      }
    Err(e) => assert_true(false, msg="canonicalise failed: \{e.to_display()}")
  }
}

test "generated headers round-trip the full pipeline" {
  let rng = prng(1004)
  let failures : Array[String] = []
  for _i = 0; _i < 300; _i = _i + 1 {
    let name = random_unicode_name(rng, 14)
    match generate_attachment(name) {
      Ok(header) => {
        match parse_content_disposition(header) {
          Ok(cd) => {
            match resolve_filename(cd) {
              Ok(sel) => {
                if sel.selected() != name {
                  failures.push("resolve mismatch for \{name}: \{sel.selected()}")
                }
                match sanitize_portable_filename(sel.selected()) {
                  Ok(safe) =>
                    if safe.safe().char_length() == 0 {
                      failures.push("empty safe name for \{name}")
                    }
                  Err(e) => failures.push("sanitise failed for \{name}: \{e.to_display()}")
                }
              }
              Err(e) => failures.push("resolve failed for \{name}: \{e.to_display()}")
            }
          }
          Err(e) => failures.push("parse failed for \{header}: \{e.to_display()}")
        }
      }
      Err(e) => failures.push("generate failed for \{name}: \{e.to_display()}")
    }
  }
  assert_true(failures.length() == 0, msg="failures: \{show_strings(failures)}")
}

test "serialise then parse keeps parameter order (1200 cases)" {
  let rng = prng(1005)
  let failures : Array[String] = []
  for _i = 0; _i < 1200; _i = _i + 1 {
    let input = make_random_cd(rng)
    match parse_content_disposition(input) {
      Ok(cd) => {
        match serialize_content_disposition(cd) {
          Ok(header) => {
            match parse_content_disposition(header) {
              Ok(again) => {
                if again.parameters().length() != cd.parameters().length() {
                  failures.push("parameter count mismatch for \{input}")
                }
                for j = 0; j < cd.parameters().length(); j = j + 1 {
                  if again.parameters()[j].name().to_lower() != cd.parameters()[j].name().to_lower() {
                    failures.push("parameter order mismatch for \{input} at \{j}")
                  }
                }
              }
              Err(e) => failures.push("re-parse failed: \{e.to_display()}")
            }
          }
          Err(e) => failures.push("serialise failed: \{e.to_display()}")
        }
      }
      Err(_) => ()
    }
  }
  assert_true(failures.length() == 0, msg="failures: \{show_strings(failures)}")
}
