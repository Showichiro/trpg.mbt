///|
fn parse_global_flags(argv : Array[String]) -> GlobalArgs {
  let args : Array[String] = []
  let mut human = false
  let mut quiet = false
  let mut describe = false
  let mut help = false
  for arg in argv {
    match arg {
      "--human" => human = true
      "--quiet" => quiet = true
      "--describe" => describe = true
      "--help" => help = true
      _ => args.push(arg)
    }
  }
  { args, human, quiet, describe, help }
}

///|
fn option_value(args : Array[String], flag : String) -> String? {
  let mut result : String? = None
  let mut i = 0
  while i < args.length() {
    if args[i] == flag && i + 1 < args.length() {
      result = Some(args[i + 1])
    }
    i += 1
  }
  result
}

///|
fn flag_present(args : Array[String], flag : String) -> Bool {
  let mut found = false
  for arg in args {
    if arg == flag {
      found = true
    }
  }
  found
}

///|
fn option_takes_value(arg : String) -> Bool {
  arg == "--from" ||
  arg == "--template" ||
  arg == "--target" ||
  arg == "--as" ||
  arg == "--stat" ||
  arg == "--bonus" ||
  arg == "--tags" ||
  arg == "--desc" ||
  arg == "--effect" ||
  arg == "--context" ||
  arg == "--by" ||
  arg == "--name" ||
  arg == "--source" ||
  arg == "--kind" ||
  arg == "--note" ||
  arg == "--ref-event" ||
  arg == "--outcome" ||
  arg == "--for-roll" ||
  arg == "--modifier" ||
  arg == "--uses" ||
  arg == "--duration" ||
  arg == "--on-trigger" ||
  arg == "--a-stat" ||
  arg == "--b-stat" ||
  arg == "--a-tags" ||
  arg == "--b-tags" ||
  arg == "--a-bonus" ||
  arg == "--b-bonus" ||
  arg == "--grant-to" ||
  arg == "--grant" ||
  arg == "--grant-name" ||
  arg == "--next-roll" ||
  arg == "--atk" ||
  arg == "--def" ||
  arg == "--damage" ||
  arg == "--atk-tags" ||
  arg == "--def-tags" ||
  arg == "--atk-bonus" ||
  arg == "--def-bonus" ||
  arg == "-n"
}

///|
fn tag_option_takes_csv(arg : String) -> Bool {
  arg == "--tags" ||
  arg == "--a-tags" ||
  arg == "--b-tags" ||
  arg == "--atk-tags" ||
  arg == "--def-tags"
}

///|
fn has_multiple_space_separated_words(value : String) -> Bool {
  let mut count = 0
  for piece in value.split(" ") {
    if !piece.is_empty() {
      count += 1
    }
  }
  count > 1
}

///|
fn validate_csv_tag_options(args : Array[String]) -> Unit raise TrpgFailure {
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if tag_option_takes_csv(arg) {
      match args.get(i + 1) {
        Some(value) => {
          if value.has_prefix("-") || has_multiple_space_separated_words(value) {
            fail(
              TrpgError::Usage(
                "invalid \{arg} value: \{value}",
                Some(
                  "multiple tags must be comma-separated, e.g. `\{arg} ritual,seal`",
                ),
              ),
            )
          }
          match args.get(i + 2) {
            Some(next) if !next.has_prefix("-") =>
              fail(
                TrpgError::Usage(
                  "invalid \{arg} syntax",
                  Some(
                    "multiple tags must be comma-separated, e.g. `\{arg} ritual,seal`",
                  ),
                ),
              )
            _ => ()
          }
        }
        None =>
          fail(
            TrpgError::Usage(
              "missing value for \{arg}",
              Some("use `\{arg} ritual,seal`"),
            ),
          )
      }
      i += 2
    } else if option_takes_value(arg) {
      i += 2
    } else {
      i += 1
    }
  }
}

///|
fn positional_args(args : Array[String]) -> Array[String] {
  let out : Array[String] = []
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if option_takes_value(arg) {
      i += 2
    } else if arg == "--if-not-exists" ||
      arg == "--brief" ||
      arg == "--prep" ||
      arg == "--scene-default" ||
      arg == "--no-consume" {
      i += 1
    } else {
      out.push(arg)
      i += 1
    }
  }
  out
}

///|
fn parse_int_arg(value : String, name : String) -> Int raise TrpgFailure {
  let parsed : Result[Int, _] = try? @string.parse_int(value)
  match parsed {
    Ok(v) => v
    Err(_) =>
      fail(
        TrpgError::Usage(
          "invalid \{name}: \{value}",
          Some("\{name} must be an integer"),
        ),
      )
  }
}
