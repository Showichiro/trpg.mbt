///|
test "validate scenario accepts structured difficulty transitions and goals" {
  let scenario = parse_json(
    "{\"id\":\"demo\",\"opening_scene\":\"entrance\",\"goals\":[{\"id\":\"seal\",\"kind\":\"scene_flag\",\"scene\":\"seal\",\"flag\":\"sealed\",\"equals\":\"true\",\"outcome\":\"success\"}],\"scenes\":{\"entrance\":{\"description\":\"入口\",\"difficulty\":{\"stat\":\"body\",\"target\":9,\"tags\":[\"forced-entry\"]},\"transitions\":[{\"to\":\"seal\",\"label\":\"進む\",\"requires\":[]}]},\"seal\":{\"description\":\"封印室\",\"difficulty\":{\"stat\":\"tech\",\"target\":11,\"tags\":[\"seal\"]},\"transitions\":[]}}}",
    "scenario",
  )
  ignore(validate_scenario_json(scenario, "demo"))
  let entrance = require_scenario_scene(scenario, "entrance")
  inspect(scene_difficulty_stat(entrance), content="Some(\"body\")")
  inspect(scene_difficulty_target(entrance), content="Some(9)")
  inspect(scene_difficulty_tags(entrance), content="[\"forced-entry\"]")
  inspect(transition_candidates(entrance).length(), content="1")
}

///|
test "derive session outcome follows success goal satisfaction" {
  inspect(
    derive_session_outcome([
      { id: "a", outcome: "success", satisfied: true, summary: "a" },
      { id: "b", outcome: "success", satisfied: true, summary: "b" },
    ]),
    content="success",
  )
  inspect(
    derive_session_outcome([
      { id: "a", outcome: "success", satisfied: true, summary: "a" },
      { id: "b", outcome: "success", satisfied: false, summary: "b" },
    ]),
    content="partial",
  )
  inspect(
    derive_session_outcome([
      { id: "a", outcome: "success", satisfied: false, summary: "a" },
    ]),
    content="failure",
  )
}
