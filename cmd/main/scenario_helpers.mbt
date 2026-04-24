///|
fn scenario_scene(scenario : Json, key : String) -> Json? {
  match json_get(scenario, "scenes") {
    Some(Object(scenes)) => scenes.get(key)
    _ => None
  }
}

///|
fn require_scenario_scene(
  scenario : Json,
  key : String,
) -> Json raise TrpgFailure {
  match scenario_scene(scenario, key) {
    Some(scene) => scene
    None =>
      fail(
        TrpgError::NotFound(
          "scene not found: \{key}",
          Some("check scenario.scenes"),
        ),
      )
  }
}

///|
fn scene_difficulty(scene : Json) -> Json? {
  match json_get(scene, "difficulty") {
    Some(Object(object)) => Some(Json::object(object))
    _ => None
  }
}

///|
fn scene_difficulty_stat(scene : Json) -> String? {
  match scene_difficulty(scene) {
    Some(difficulty) => json_string_opt_field(difficulty, "stat")
    None => None
  }
}

///|
fn scene_difficulty_target(scene : Json) -> Int? {
  match scene_difficulty(scene) {
    Some(difficulty) => json_int_opt_field(difficulty, "target")
    None => None
  }
}

///|
fn scene_difficulty_tags(scene : Json) -> Array[String] {
  match scene_difficulty(scene) {
    Some(difficulty) => json_string_array_field(difficulty, "tags")
    None => []
  }
}

///|
fn current_scene_description(scenario : Json, key : String) -> String {
  match scenario_scene(scenario, key) {
    Some(scene) => {
      let desc = json_string_field(scene, "description", "")
      match scene_difficulty(scene) {
        Some(difficulty) => {
          let stat = json_string_field(difficulty, "stat", "")
          let target = json_int_field(difficulty, "target", 0)
          if stat.is_empty() || target == 0 {
            desc
          } else {
            desc + "\n難易度目安: \{stat} \{target}"
          }
        }
        None => desc
      }
    }
    None => ""
  }
}

///|
fn validate_scenario_json(
  scenario : Json,
  scenario_id : String,
) -> Unit raise TrpgFailure {
  let opening = json_string_field(scenario, "opening_scene", "")
  if opening.is_empty() {
    fail(
      TrpgError::Usage(
        "scenario missing opening_scene: \{scenario_id}",
        Some("define opening_scene"),
      ),
    )
  }
  ignore(require_scenario_scene(scenario, opening))
  match json_get(scenario, "scenes") {
    Some(Object(scenes)) =>
      for key, scene in scenes {
        for transition in json_array_field(scene, "transitions") {
          let to = json_string_field(transition, "to", "")
          if to.is_empty() {
            fail(
              TrpgError::Usage(
                "transition missing `to` in scene \{key}",
                Some("define transitions[].to"),
              ),
            )
          }
          let exists = match scenes.get(to) {
            Some(_) => true
            None => false
          }
          if !exists {
            fail(
              TrpgError::Usage(
                "transition points to unknown scene: \{key} -> \{to}",
                Some("fix scenario transitions"),
              ),
            )
          }
        }
      }
    _ =>
      fail(
        TrpgError::Usage(
          "scenario missing scenes: \{scenario_id}",
          Some("define scenario.scenes"),
        ),
      )
  }
}

///|
fn transition_candidates(scene : Json) -> Array[Json] {
  json_array_field(scene, "transitions")
}

///|
fn item_matches_id(item : Json, item_id : String) -> Bool {
  let current_id = json_string_field(item, "id", object_name(item, "item"))
  current_id == item_id || object_name(item, "item") == item_id
}

///|
fn actor_has_item_id(
  row : CharacterRow,
  item_id : String,
) -> Bool raise TrpgFailure {
  let items = item_objects_from_sheet_json(row.sheet_json)
  let mut found = false
  for item in items {
    if item_matches_id(item, item_id) {
      found = true
    }
  }
  found
}

///|
fn event_item_matches_id(event : EventRow, item_id : String) -> Bool {
  let data = parse_json(event.data_json, "event.data_json") catch {
    _ => Json::object({})
  }
  let current_id = json_string_field(
    data,
    "item_id",
    json_string_field(data, "item", ""),
  )
  current_id == item_id || json_string_field(data, "item", "") == item_id
}

///|
fn actor_ever_had_item_id(
  db : @sqlite.Database,
  session : SessionRow,
  actor : String,
  item_id : String,
) -> Bool raise TrpgFailure {
  if actor == "any_pc" {
    let pcs = list_characters(db, session.id).filter(row => row.kind == "pc")
    for row in pcs {
      if actor_has_item_id(row, item_id) {
        return true
      }
    }
    let events = list_events(db, session.id, Some("item"), None, 10000)
    for event in events {
      let is_pc = match event.subject {
        Some(name) => string_array_contains(pcs.map(row => row.name), name)
        None => false
      }
      if is_pc && event_item_matches_id(event, item_id) {
        return true
      }
    }
    false
  } else {
    let row = require_character(db, session.id, actor)
    if actor_has_item_id(row, item_id) {
      true
    } else {
      let events = list_events(db, session.id, Some("item"), None, 10000)
      let mut found = false
      for event in events {
        if event.subject == Some(actor) && event_item_matches_id(event, item_id) {
          found = true
        }
      }
      found
    }
  }
}

///|
fn condition_satisfied(
  db : @sqlite.Database,
  session : SessionRow,
  condition : Json,
) -> Bool raise TrpgFailure {
  match json_string_field(condition, "kind", "") {
    "inventory_contains" => {
      let actor = json_string_field(condition, "actor", "any_pc")
      let item_id = json_string_field(condition, "item_id", "")
      if item_id.is_empty() {
        false
      } else if actor == "any_pc" {
        let mut found = false
        for row in list_characters(db, session.id) {
          if row.kind == "pc" && actor_has_item_id(row, item_id) {
            found = true
          }
        }
        found
      } else {
        actor_has_item_id(require_character(db, session.id, actor), item_id)
      }
    }
    "inventory_ever_contained" => {
      let actor = json_string_field(condition, "actor", "any_pc")
      let item_id = json_string_field(condition, "item_id", "")
      if item_id.is_empty() {
        false
      } else {
        actor_ever_had_item_id(db, session, actor, item_id)
      }
    }
    "scene_flag" => {
      let scene_key = json_string_field(
        condition,
        "scene",
        session.current_scene,
      )
      let flag = json_string_field(condition, "flag", "")
      let expected = json_string_field(condition, "equals", "")
      if flag.is_empty() {
        false
      } else {
        let flags = load_scene_flags(db, session.id, scene_key)
        match flags.get(flag) {
          Some(String(value)) => value == expected
          Some(True) => expected == "true"
          Some(False) => expected == "false"
          _ => false
        }
      }
    }
    "scene_progress_at_least" => {
      let scene_key = json_string_field(
        condition,
        "scene",
        session.current_scene,
      )
      let progress_key = json_string_field(condition, "key", "")
      let expected = json_int_field(condition, "value", 0)
      if progress_key.is_empty() {
        false
      } else {
        let progress = load_scene_progress(db, session.id, scene_key)
        match progress.get(progress_key) {
          Some(value) => value >= expected
          None => false
        }
      }
    }
    _ => false
  }
}

///|
fn goal_statuses(
  db : @sqlite.Database,
  session : SessionRow,
  scenario : Json,
) -> Array[GoalStatusRow] raise TrpgFailure {
  let rows : Array[GoalStatusRow] = []
  for goal in json_array_field(scenario, "goals") {
    let id = json_string_field(goal, "id", "goal")
    let outcome = json_string_field(goal, "outcome", "success")
    let satisfied = condition_satisfied(db, session, goal)
    let summary = match json_string_field(goal, "kind", "") {
      "inventory_contains" => {
        let item_id = json_string_field(goal, "item_id", "")
        "inventory_contains(\{item_id})"
      }
      "inventory_ever_contained" => {
        let item_id = json_string_field(goal, "item_id", "")
        "inventory_ever_contained(\{item_id})"
      }
      "scene_flag" => {
        let scene_key = json_string_field(goal, "scene", "")
        let flag = json_string_field(goal, "flag", "")
        "scene_flag(\{scene_key}.\{flag})"
      }
      "scene_progress_at_least" => {
        let scene_key = json_string_field(goal, "scene", "")
        let progress_key = json_string_field(goal, "key", "")
        let expected = json_int_field(goal, "value", 0)
        "scene_progress_at_least(\{scene_key}.\{progress_key} >= \{expected})"
      }
      other => other
    }
    rows.push({ id, outcome, satisfied, summary })
  }
  rows
}

///|
fn goal_status_json(goal : GoalStatusRow) -> Json {
  Json::object({
    "id": Json::string(goal.id),
    "outcome": Json::string(goal.outcome),
    "satisfied": Json::boolean(goal.satisfied),
    "summary": Json::string(goal.summary),
  })
}

///|
fn format_goal_statuses(goals : Array[GoalStatusRow]) -> String {
  if goals.length() == 0 {
    "(なし)"
  } else {
    goals
    .map(goal => {
      let mark = if goal.satisfied { "x" } else { " " }
      "- [\{mark}] \{goal.id} (\{goal.outcome}) \{goal.summary}"
    })
    .join("\n")
  }
}

///|
fn derive_session_outcome(goals : Array[GoalStatusRow]) -> String {
  if goals.length() == 0 {
    "partial"
  } else {
    let success_goals = goals.filter(goal => goal.outcome == "success")
    if success_goals.length() == 0 {
      "partial"
    } else {
      let satisfied = success_goals.filter(goal => goal.satisfied)
      if satisfied.length() == success_goals.length() {
        "success"
      } else if satisfied.length() == 0 {
        "failure"
      } else {
        "partial"
      }
    }
  }
}

///|
fn available_scene_transitions(
  db : @sqlite.Database,
  session : SessionRow,
  scenario : Json,
) -> Array[Json] raise TrpgFailure {
  let scene = require_scenario_scene(scenario, session.current_scene)
  let out : Array[Json] = []
  for transition in transition_candidates(scene) {
    let mut ok = true
    for requirement in json_array_field(transition, "requires") {
      if !condition_satisfied(db, session, requirement) {
        ok = false
      }
    }
    if ok {
      out.push(transition)
    }
  }
  out
}

///|
fn format_scene_transition(transition : Json) -> String {
  let to = json_string_field(transition, "to", "")
  let label = json_string_field(transition, "label", "")
  if label.is_empty() {
    "- \{to}"
  } else {
    "- \{to}: \{label}"
  }
}

///|
fn format_scene_summary(key : String, scene : Json, current : Bool) -> String {
  let prefix = if current { "* " } else { "- " }
  let desc = json_string_field(scene, "description", "")
  let difficulty = match scene_difficulty(scene) {
    Some(info) => {
      let stat = json_string_field(info, "stat", "")
      let target = json_int_field(info, "target", 0)
      if stat.is_empty() || target == 0 {
        ""
      } else {
        " / 難易度: \{stat} \{target}"
      }
    }
    None => ""
  }
  prefix + "\{key}: \{desc}\{difficulty}"
}
