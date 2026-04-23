///|
fn parse_global_flags(argv : Array[String]) -> GlobalArgs {
  let args : Array[String] = []
  let mut human = false
  let mut quiet = false
  let mut describe = false
  for arg in argv {
    match arg {
      "--human" => human = true
      "--quiet" => quiet = true
      "--describe" => describe = true
      _ => args.push(arg)
    }
  }
  { args, human, quiet, describe }
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
  arg == "--target" ||
  arg == "--as" ||
  arg == "--context" ||
  arg == "--by" ||
  arg == "--note" ||
  arg == "--for-roll" ||
  arg == "--modifier" ||
  arg == "--uses" ||
  arg == "--duration" ||
  arg == "--on-trigger" ||
  arg == "-n"
}

///|
fn positional_args(args : Array[String]) -> Array[String] {
  let out : Array[String] = []
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if option_takes_value(arg) {
      i += 2
    } else if arg == "--if-not-exists" {
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
