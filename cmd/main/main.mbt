///|
const VERSION : String = "0.1.0"

///|
async fn main {
  let args = @env.args()
  let argv = if args.length() > 1 { args[1:].to_array() } else { [] }
  let result = run(argv)
  if !result.stderr.is_empty() {
    write_stderr(result.stderr)
    if !result.stderr.has_suffix("\n") {
      write_stderr("\n")
    }
  }
  if !result.stdout.is_empty() {
    write_stdout(result.stdout)
    if !result.stdout.has_suffix("\n") {
      write_stdout("\n")
    }
  }
  @sys.exit(result.exit_code)
}

///|
async fn run(argv : Array[String]) -> RunResult {
  try {
    let global = parse_global_flags(argv)
    if global.help {
      return help_output(global)
    }
    if global.describe {
      return json_success(
        describe_commands_json(),
        "trpg CLI コマンド一覧",
        global,
      )
    }
    if global.args.length() == 0 {
      return error_output(
        TrpgError::Usage(
          "missing command",
          Some("run `trpg --describe` to inspect supported commands"),
        ),
      )
    }
    validate_csv_tag_options(global.args)
    match global.args[0] {
      "version" => {
        let out = Json::object({ "command": "version", "version": VERSION })
        json_success(out, VERSION, global)
      }
      "session" => dispatch_session(global)
      "pc" => dispatch_pc(global)
      "roll" => dispatch_roll(global)
      "contest" => dispatch_contest(global)
      "attack" => dispatch_attack(global)
      "hp" => dispatch_hp(global)
      "status" => dispatch_status(global)
      "item" => dispatch_item(global)
      "log" => dispatch_log(global)
      "scene" => dispatch_scene(global)
      "scenario" => dispatch_scenario(global)
      "prompt" => dispatch_prompt(global)
      other =>
        error_output(
          TrpgError::Usage(
            "unknown command: \{other}",
            Some("run `trpg --describe` to inspect supported commands"),
          ),
        )
    }
  } catch {
    TrpgFailure(err) => error_output(err)
  }
}
