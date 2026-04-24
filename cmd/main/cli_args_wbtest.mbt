///|
test "positional args skip option values" {
  let args = [
    "roll", "2d6+3", "--target", "10", "--as", "alice", "--if-not-exists",
  ]
  inspect(positional_args(args), content="[\"roll\", \"2d6+3\"]")
}

///|
test "global flags are removed from command args" {
  let parsed = parse_global_flags(["--describe", "--human", "session", "show"])
  inspect(parsed.describe, content="true")
  inspect(parsed.human, content="true")
  inspect(parsed.args, content="[\"session\", \"show\"]")
}

///|
test "csv tag options accept comma-separated values" {
  validate_csv_tag_options([
    "status", "alice", "add", "儀式譜面", "--tags", "ritual,seal", "--uses",
    "1",
  ])
}

///|
test "csv tag options reject whitespace-separated trailing tags" {
  let err = try? validate_csv_tag_options([
    "status", "alice", "add", "儀式譜面", "--tags", "ritual", "seal",
  ])
  inspect(
    match err {
      Ok(_) => false
      Err(_) => true
    },
    content="true",
  )
}
