// invalid_input_test.mbt — Malformed inputs and their exact (stage, kind)
// error classification.

test "malformed inputs map to the documented stages and kinds" {
  let cases : Array[(String, String, String)] = [
    ("", "Input", "EmptyInput"),
    ("   ", "Input", "EmptyInput"),
    ("\t ", "Input", "EmptyInput"),
    ("; filename=x", "DispositionType", "InvalidDispositionType"),
    ("attachment;", "ParameterName", "ExpectedToken"),
    ("attachment;;", "ParameterName", "ExpectedToken"),
    ("attachment; =x", "ParameterName", "ExpectedToken"),
    ("attachment; \"x\"", "ParameterName", "ExpectedToken"),
    ("attachment; size", "ParameterName", "MissingEquals"),
    ("attachment; size=", "ParameterValue", "MissingParameterValue"),
    ("attachment; size=\"unterminated", "QuotedString", "UnterminatedQuotedString"),
    ("attachment; size=\"a\u{0000}b\"", "QuotedString", "InvalidControlCharacter"),
    ("attachment; size=\"a\rb\"", "QuotedString", "InvalidControlCharacter"),
    ("attachment; size=\"a\nb\"", "QuotedString", "InvalidControlCharacter"),
    ("attachment; size=\"a\\\u{0000}b\"", "QuotedString", "InvalidQuotedPair"),
    ("attachment; size=x y", "Input", "TrailingInput"),
    ("attachment !", "Input", "TrailingInput"),
    ("attachment; size=a\u{0000}b", "Input", "TrailingInput"),
    ("attachment; filename*=UTF-8''a b", "Input", "TrailingInput"),
    ("attachment; filename*=UTF-8''a\\b", "Input", "TrailingInput"),
    ("attachment; filename*='abc", "ExtendedValue", "MissingCharset"),
    ("attachment; filename*=UTF-8'abc", "ExtendedValue", "InvalidExtendedValue"),
    ("attachment; filename*=UTF-8''a%2G", "ExtendedValue", "InvalidPercentEncoding"),
    ("attachment; filename*=UTF-8''a%2", "ExtendedValue", "InvalidPercentEncoding"),
    ("attachment; filename*=UTF-8''%FF", "Charset", "InvalidUtf8"),
    ("attachment; filename*=SHIFT-JIS''a", "ExtendedValue", "UnsupportedCharset"),
    ("attachment; filename*=UTF-8''a b", "Input", "TrailingInput"),
  ]
  for pair in cases {
    let (input, stage, kind) = pair
    expect_parse_error(input, stage, kind)
  }
}

test "a CRLF-injected header value is rejected as trailing input" {
  // CR/LF are never treated as whitespace, so a header value carrying a
  // line break cannot smuggle a second parameter.
  expect_parse_error("attachment; filename=a\r\nb", "Input", "TrailingInput")
  expect_parse_error("attachment\r\n; filename=b", "Input", "TrailingInput")
}

test "a quoted parameter cannot terminate a second parameter" {
  // The ';' inside a quoted string is data, not a separator, so there is
  // no injection vector through quoted values.
  expect_parse("attachment; name=\"a;b\"", "attachment; name=\"a;b\"")
  expect_parse("attachment; name=\"a\\\";b\"", "attachment; name=\"a\\\";b\"")
}

test "empty extended value charset is rejected even with a value" {
  expect_parse_error("attachment; filename*='a", "ExtendedValue", "MissingCharset")
}

test "a reserved char cannot start a parameter" {
  expect_parse_error("attachment; ?x=1", "ParameterName", "ExpectedToken")
}
