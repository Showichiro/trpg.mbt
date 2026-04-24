///|
fn test_scenario_json(id : String) -> String {
  "{\"id\":\"\{id}\",\"title\":\"Demo\",\"summary\":\"demo\",\"opening_scene\":\"entrance\",\"scenes\":{\"entrance\":{\"description\":\"入口\",\"transitions\":[]}}}"
}

///|
test "scenario id falls back to filename when json id is absent" {
  let scenario = parse_json(
    "{\"title\":\"Demo\",\"opening_scene\":\"entrance\",\"scenes\":{\"entrance\":{\"description\":\"入口\",\"transitions\":[]}}}",
    "scenario",
  )
  inspect(
    scenario_id_from_json_or_fallback(scenario, "fallback_demo"),
    content="fallback_demo",
  )
}

///|
async test "load scenario source supports local path" {
  let base = "/tmp/trpg-scenario-source-\{now_ms().to_string()}"
  ignore(@fs.create_dir(base) catch { _ => () })
  let path = base + "/demo.json"
  write_text_file(path, test_scenario_json("local_demo"))
  let source = load_scenario_source(path)
  inspect(source.scenario_id, content="local_demo")
  inspect(source.source_kind, content="path")
  inspect(source.source_label, content=path)
}
