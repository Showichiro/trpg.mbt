///|
fn TrpgError::exit_code(self : TrpgError) -> Int {
  match self {
    Usage(_, _) => 2
    General(_, _) => 1
    NotFound(_, _) => 3
    Permission(_, _) => 4
    Conflict(_, _) => 5
  }
}

///|
fn TrpgError::code(self : TrpgError) -> String {
  match self {
    Usage(_, _) => "usage_error"
    General(_, _) => "general_error"
    NotFound(_, _) => "resource_not_found"
    Permission(_, _) => "permission_denied"
    Conflict(_, _) => "conflict"
  }
}

///|
fn TrpgError::message(self : TrpgError) -> String {
  match self {
    Usage(message, _)
    | General(message, _)
    | NotFound(message, _)
    | Permission(message, _)
    | Conflict(message, _) => message
  }
}

///|
fn TrpgError::suggestion(self : TrpgError) -> String? {
  match self {
    Usage(_, suggestion)
    | General(_, suggestion)
    | NotFound(_, suggestion)
    | Permission(_, suggestion)
    | Conflict(_, suggestion) => suggestion
  }
}

///|
fn TrpgError::to_json(self : TrpgError) -> Json {
  let object : Map[String, Json] = {
    "error": Json::string(self.code()),
    "message": Json::string(self.message()),
  }
  match self.suggestion() {
    Some(suggestion) => object["suggestion"] = Json::string(suggestion)
    None => ()
  }
  Json::object(object)
}

///|
fn error_output(err : TrpgError) -> RunResult {
  {
    stdout: err.to_json().stringify(),
    stderr: "エラー: \{err.message()}",
    exit_code: err.exit_code(),
  }
}

///|
fn output_success(output : CliOutput, global : GlobalArgs) -> RunResult {
  let stdout = if global.human {
    output.human
  } else if global.quiet {
    output.json.stringify()
  } else {
    output.json.stringify()
  }
  {
    stdout,
    stderr: if global.quiet {
      ""
    } else {
      output.stderr
    },
    exit_code: 0,
  }
}

///|
fn json_success(json : Json, human : String, global : GlobalArgs) -> RunResult {
  output_success({ json, human, stderr: human }, global)
}

///|
fn[A] fail(err : TrpgError) -> A raise TrpgFailure {
  raise TrpgFailure(err)
}
