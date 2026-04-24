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
  arg == "--note" ||
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
fn positional_args(args : Array[String]) -> Array[String] {
  let out : Array[String] = []
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if option_takes_value(arg) {
      i += 2
    } else if arg == "--if-not-exists" ||
      arg == "--brief" ||
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
