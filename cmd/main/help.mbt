///|
fn command_help_key(args : Array[String]) -> String? {
  match args.get(0) {
    None => None
    Some("contest") => Some("contest")
    Some("attack") => Some("attack")
    Some("version") => Some("version")
    Some("roll") =>
      match args.get(1) {
        Some("history") => Some("roll.history")
        _ => Some("roll")
      }
    Some("session") =>
      match args.get(1) {
        Some(verb) => Some("session." + verb)
        None => None
      }
    Some("pc") =>
      match args.get(1) {
        Some("style") =>
          match args.get(2) {
            Some(verb) => Some("pc.style." + verb)
            None => None
          }
        Some("templates") =>
          match args.get(2) {
            Some(verb) => Some("pc.templates." + verb)
            None => None
          }
        Some(verb) => Some("pc." + verb)
        None => None
      }
    Some("item") =>
      match args.get(1) {
        Some(verb) => Some("item." + verb)
        None => None
      }
    Some("log") =>
      match args.get(1) {
        Some(verb) => Some("log." + verb)
        None => None
      }
    Some("scene") =>
      match args.get(1) {
        Some("modifier") =>
          match args.get(2) {
            Some(verb) => Some("scene.modifier." + verb)
            None => None
          }
        Some(verb) => Some("scene." + verb)
        None => None
      }
    Some("scenario") =>
      match args.get(1) {
        Some(verb) => Some("scenario." + verb)
        None => None
      }
    Some("prompt") =>
      match args.get(1) {
        Some(verb) => Some("prompt." + verb)
        None => None
      }
    Some("hp") => Some("hp")
    Some("status") => Some("status")
    Some(_) => None
  }
}

///|
fn help_output(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let doc = describe_commands_json()
  let commands = json_object_field(doc, "commands")
  let positions = positional_args(global.args)
  match command_help_key(positions) {
    Some(key) =>
      match commands.get(key) {
        Some(descriptor) => {
          let summary = json_string_field(descriptor, "summary", "")
          let usage = json_string_field(descriptor, "usage", "")
          let human = key + "\n" + summary + "\nusage: " + usage
          output_success({ json: descriptor, human, stderr: human }, global)
        }
        None =>
          fail(
            TrpgError::Usage(
              "help is not available for this command",
              Some("run `trpg --describe` to inspect supported commands"),
            ),
          )
      }
    None => {
      let human = "trpg CLI\n\n" +
        "top-level commands:\n" +
        "- session\n- pc\n- roll\n- contest\n- attack\n- hp\n- status\n- item\n- log\n- scene\n- scenario\n- prompt\n\n" +
        "use `trpg <command> --help` or `trpg --describe`."
      output_success({ json: doc, human, stderr: human }, global)
    }
  }
}
