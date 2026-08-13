// model_test.mbt — The core value model: types, accessors, equality and
// rendering. Models are built through the public parse API so the tests stay
// black-box (the blackbox test package cannot name enum variants in
// expression position in MoonBit 0.1.2026).

test "library version is a single source of truth" {
  inspect(library_version(), content="0.1.0")
}

test "disposition type lower names" {
  let a = parse_content_disposition("inline").unwrap()
  inspect(a.disposition_type().to_lower_name(), content="inline")
  let b = parse_content_disposition("attachment").unwrap()
  inspect(b.disposition_type().to_lower_name(), content="attachment")
  let c = parse_content_disposition("FormData").unwrap()
  inspect(c.disposition_type().to_lower_name(), content="formdata")
  let d = parse_content_disposition("x-custom").unwrap()
  inspect(d.disposition_type().to_lower_name(), content="x-custom")
}

test "disposition type predicates" {
  let inline = parse_content_disposition("inline").unwrap()
  assert_true(inline.disposition_type().is_inline())
  assert_false(inline.disposition_type().is_attachment())
  assert_false(inline.disposition_type().is_extension())
  let attachment = parse_content_disposition("attachment").unwrap()
  assert_true(attachment.disposition_type().is_attachment())
  assert_false(attachment.disposition_type().is_inline())
  let ext = parse_content_disposition("custom").unwrap()
  assert_true(ext.disposition_type().is_extension())
}

test "extension name accessor" {
  let cd = parse_content_disposition("FormData").unwrap()
  match cd.disposition_type().extension_name() {
    Some(n) => inspect(n, content="FormData")
    None => assert_true(false, msg="expected an extension name")
  }
  let inline = parse_content_disposition("inline").unwrap()
  assert_true(inline.disposition_type().extension_name() is None)
  let attachment = parse_content_disposition("attachment").unwrap()
  assert_true(attachment.disposition_type().extension_name() is None)
}

test "matches is case-insensitive" {
  let form = parse_content_disposition("form-data").unwrap()
  assert_true(form.disposition_type().matches("Form-Data"))
  assert_true(form.disposition_type().matches("FORM-DATA"))
  assert_false(form.disposition_type().matches("FormData"))
  assert_false(form.disposition_type().matches("other"))
  let attachment = parse_content_disposition("attachment").unwrap()
  assert_true(attachment.disposition_type().matches("ATTACHMENT"))
  let inline = parse_content_disposition("inline").unwrap()
  assert_true(inline.disposition_type().matches("inline"))
  assert_false(attachment.disposition_type().matches("inline"))
}

test "parameter value plain accessors" {
  let tok = parse_content_disposition("attachment; size=v").unwrap()
  let tv = tok.get_parameter("size").unwrap()
  match tv.value().plain() {
    Some(v) => inspect(v, content="v")
    None => assert_true(false, msg="Token should have a plain value")
  }
  assert_true(tv.value().extended() is None)
  assert_false(tv.value().is_extended())
  let q = parse_content_disposition("attachment; name=\"a b\"").unwrap()
  let qv = q.get_parameter("name").unwrap()
  match qv.value().plain() {
    Some(v) => inspect(v, content="a b")
    None => assert_true(false, msg="Quoted should have a plain value")
  }
  let ev = parse_content_disposition("attachment; filename*=UTF-8''caf%C3%A9").unwrap()
  let evp = ev.get_parameter("filename*").unwrap()
  assert_true(evp.value().is_extended())
  assert_true(evp.value().plain() is None)
  match evp.value().extended() {
    Some(x) => inspect(x.charset(), content="UTF-8")
    None => assert_true(false, msg="Extended should have an extended value")
  }
}

test "content disposition accessors" {
  let cd = parse_content_disposition("attachment").unwrap()
  inspect(cd.disposition_type().to_lower_name(), content="attachment")
  inspect(cd.parameter_count(), content="0")
  inspect(cd.to_debug_string(), content="attachment")
}

test "get_parameter lookup is case-insensitive and first-wins" {
  // Duplicate parameters require compatible mode; strict mode rejects them.
  let cd = parse_compatible("attachment; FILENAME=one; filename=two")
  match cd.get_parameter("filename") {
    Some(p) => inspect(p.name(), content="FILENAME")
    None => assert_true(false, msg="filename should be found")
  }
  match cd.get_parameter("Filename") {
    Some(p) => inspect(p.name(), content="FILENAME")
    None => assert_true(false, msg="case-insensitive lookup should find FILENAME")
  }
  assert_true(cd.get_parameter("missing") is None)
}

test "filename and filename_star accessors" {
  let cd = parse_content_disposition(
    "attachment; filename=\"a.txt\"; filename*=UTF-8''caf%C3%A9.txt",
  ).unwrap()
  match cd.filename() {
    Some(v) => inspect(v, content="a.txt")
    None => assert_true(false, msg="filename should be present")
  }
  match cd.filename_star() {
    Some(ev) => inspect(ev.value(), content="café.txt")
    None => assert_true(false, msg="filename* should be present")
  }
}

test "to_debug_string renders token, quoted and extended values" {
  // Parse round-trip: the model renders token, quoted and extended values in
  // a compact, deterministic form. Duplicate names need compatible mode.
  let parsed = parse_compatible(
    "attachment; filename=report.pdf; filename=\"with space.txt\"; filename*=UTF-8'en'caf%C3%A9",
  )
  expect_cd(parsed, "attachment; filename=report.pdf; filename=\"with space.txt\"; filename*=UTF-8'en'café")
}

test "semantic equality is order-sensitive and case-insensitive on names" {
  let a = parse_compatible("attachment; filename=a.txt; filename=b.txt")
  let b = parse_compatible("attachment; FILENAME=a.txt; FILENAME=b.txt")
  assert_true(a.semantic_equal(b))
  let c = parse_compatible("attachment; filename=b.txt; filename=a.txt")
  assert_false(a.semantic_equal(c))
  let d = parse_compatible("inline; filename=a.txt; filename=b.txt")
  assert_false(a.semantic_equal(d))
}

test "semantic equality compares parameter values exactly" {
  let a = parse_content_disposition("attachment; filename=a.txt").unwrap()
  let b = parse_content_disposition("attachment; filename=a.txt; size=1").unwrap()
  assert_false(a.semantic_equal(b))
  let c = parse_content_disposition("attachment; size=1").unwrap()
  assert_false(a.semantic_equal(c))
}

test "extension type preserved verbatim in the model" {
  let cd = parse_content_disposition("form-data; name=\"field\"").unwrap()
  match cd.disposition_type() {
    Extension(name) => inspect(name, content="form-data")
    _ => assert_true(false, msg="expected an extension type")
  }
}

test "parameter_count and parameters preserve order" {
  let cd = parse_compatible("attachment; size=1; name=\"x\"; size=2")
  inspect(cd.parameter_count(), content="3")
  let names : Array[String] = []
  for p in cd.parameters() {
    names.push(p.name())
  }
  expect_same_strings(names, ["size", "name", "size"])
}

test "parameter values classify as token, quoted and extended" {
  let cd = parse_content_disposition(
    "attachment; a=token; b=\"quoted\"; c*=UTF-8''x",
  ).unwrap()
  let kinds : Array[String] = []
  for p in cd.parameters() {
    match p.value() {
      Token(_) => kinds.push("token")
      Quoted(_) => kinds.push("quoted")
      Extended(_) => kinds.push("extended")
    }
  }
  expect_same_strings(kinds, ["token", "quoted", "extended"])
}
