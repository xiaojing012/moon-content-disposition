// parser.mbt — RFC 6266 Content-Disposition header value parser.
//
// Grammar (RFC 6266 Section 4.2, applied to the header field value, i.e.
// the part after the field name and colon):
//
//     disposition-type    = "inline" / "attachment" / disp-ext-type
//     disposition-parm    = filename-parm / disp-ext-parm
//     filename-parm       = "filename" "=" value
//                         / "filename*" "=" ext-value
//     disp-ext-parm       = token "=" value / ext-token "=" ext-value
//     value               = token / quoted-string
//
// Optional whitespace (SP / HTAB) is permitted around the `;` separators
// and around the `=` sign, matching RFC 7230 field-value conventions; this
// is documented in `docs/compatibility.md`. CR and LF are never treated as
// whitespace.
//
// Duplicate parameter names are rejected in strict mode (RFC 6266 leaves
// the behaviour undefined; strict mode refuses to guess) and preserved
// with a recorded duplicate in compatible mode. Every public entry point
// returns `Result[T, DispositionError]`; internal functions raise.

///|
/// The detailed result of parsing a Content-Disposition header value:
/// the model plus the duplicate names and compatible recoveries observed.
pub struct DispositionParse {
  content_disposition : ContentDisposition
  duplicates : Array[String]
  recoveries : Array[String]
  mode : ParseMode
}

///|
/// The parsed Content-Disposition value.
pub fn DispositionParse::content_disposition(self : DispositionParse) -> ContentDisposition {
  self.content_disposition
}

///|
/// The names of duplicated parameters (compatible mode), in detection
/// order, each at most once.
pub fn DispositionParse::duplicates(self : DispositionParse) -> Array[String] {
  self.duplicates
}

///|
/// The compatible recoveries applied during the parse, in application
/// order, each at most once. Empty in strict mode.
pub fn DispositionParse::recoveries(self : DispositionParse) -> Array[String] {
  self.recoveries
}

///|
/// The parse mode used for this parse.
pub fn DispositionParse::mode(self : DispositionParse) -> ParseMode {
  self.mode
}

///|
/// Parses a Content-Disposition header field value in strict mode with
/// default limits.
///
/// Errors: `Input::EmptyInput` (empty value), `Input::LimitExceeded`
/// (input larger than `max_input_bytes`), `Limit::LimitExceeded`, plus the
/// `DispositionType`, `ParameterName`, `ParameterValue`, `QuotedString`,
/// `ExtendedValue`, `Charset` and `PercentEncoding` errors raised while
/// parsing.
pub fn parse_content_disposition(input : String) -> Result[ContentDisposition, DispositionError] {
  parse_content_disposition_with_options(input, ParseOptions::default())
}

///|
/// Parses a Content-Disposition header field value with explicit options.
pub fn parse_content_disposition_with_options(
  input : String,
  options : ParseOptions
) -> Result[ContentDisposition, DispositionError] {
  match parse_content_disposition_detailed(input, options) {
    Ok(p) => Ok(p.content_disposition)
    Err(e) => Err(e)
  }
}

///|
/// Parses a Content-Disposition header field value with explicit options,
/// also returning duplicate names and compatible recoveries.
pub fn parse_content_disposition_detailed(
  input : String,
  options : ParseOptions
) -> Result[DispositionParse, DispositionError] {
  let limits = options.limits()
  let mode = options.mode()
  let bytes = @utf8.encode(input)
  if bytes.length() > limits.max_input_bytes() {
    return Err(
      disposition_error(
        Input,
        LimitExceeded,
        "input exceeds max_input_bytes (\{limits.max_input_bytes()} bytes)",
      ),
    )
  }
  let cursor = Scanner::new(input)
  cursor.skip_ows()
  if cursor.eof() {
    return Err(disposition_error(Input, EmptyInput, "empty Content-Disposition value"))
  }
  let collector = ParseCollector::new()
  let (dt, raw_type) = try {
    unwrap_or_raise(parse_disposition_type(cursor))
  } catch {
    e => return Err(unwrap_disposition_error(e))
  }
  let cd = content_disposition_with_raw(dt, raw_type)
  let mut done = false
  let mut last_was_empty = false
  while !done {
    cursor.skip_ows()
    if cursor.eof() {
      done = true
    } else if cursor.consume_char(59) {
      // ';'
      cursor.skip_ows()
      if cursor.eof() {
        // trailing ';' with no following parameter. When the separator run
        // was already reported as an empty element (';;' at the end), there
        // is no separate trailing-semicolon recovery.
        if mode == Compatible {
          if !last_was_empty {
            collector.record_recovery("trailing-semicolon")
          }
          done = true
        } else {
          return Err(
            disposition_error_at(
              ParameterName,
              ExpectedToken,
              cursor.position(),
              "expected a parameter after ';'",
            ),
          )
        }
      } else {
        match cursor.peek_byte() {
          Some(b) if b == 59 => {
            // empty parameter element (';;'): no name
            if mode == Compatible {
              collector.record_recovery("skip-empty-parameter")
              last_was_empty = true
            } else {
              return Err(
                disposition_error_at(
                  ParameterName,
                  ExpectedToken,
                  cursor.position(),
                  "expected a parameter after ';'",
                ),
              )
            }
          }
          _ => {
            last_was_empty = false
            let param_start = cursor.position()
            let param = try {
              unwrap_or_raise(parse_parameter(cursor, limits, mode, collector))
            } catch {
              e => return Err(unwrap_disposition_error(e))
            }
            if collector.has_seen(param.name) {
              if mode == Strict {
                return Err(
                  disposition_error_at(
                    ParameterName,
                    DuplicateParameter,
                    param_start,
                    "duplicate parameter '\{param.name}'",
                  ),
                )
              }
              collector.record_duplicate(param.name)
            } else {
              collector.mark_seen(param.name)
            }
            cd.parameters.push(param)
            if cd.parameters.length() > limits.max_parameters() {
              return Err(
                disposition_error_at(
                  Limit,
                  LimitExceeded,
                  param_start,
                  "too many parameters (exceeds max_parameters)",
                ),
              )
            }
          }
        }
      }
    } else {
      return Err(
        disposition_error_at(Input, TrailingInput, cursor.position(), cursor.context_string()),
      )
    }
  }
  Ok({
    content_disposition: cd,
    duplicates: collector.duplicates(),
    recoveries: collector.recoveries(),
    mode,
  })
}

// Parses the leading disposition type token, returning the typed value
// together with the raw token exactly as it appeared on the wire so that a
// preserve-case serialisation can reproduce the original spelling.
fn parse_disposition_type(
  cursor : Scanner
) -> Result[(DispositionType, String), DispositionError] raise {
  let (ts, te) = cursor.consume_token()
  if te == ts {
    raise disposition_error_at(
      DispositionType,
      InvalidDispositionType,
      cursor.position(),
      "expected a disposition type token",
    )
  }
  let name = cursor.take_string(ts, te)
  let dt = if name.equal_ignore_ascii_case("inline") {
    Inline
  } else if name.equal_ignore_ascii_case("attachment") {
    Attachment
  } else {
    Extension(name)
  }
  Ok((dt, name))
}
