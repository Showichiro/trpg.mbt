///|
fn need_pos(
  args : Array[String],
  index : Int,
  label : String,
) -> String raise TrpgFailure {
  match args.get(index) {
    Some(value) => value
    None =>
      fail(
        TrpgError::Usage(
          "missing \{label}",
          Some("run `trpg --describe` to inspect command usage"),
        ),
      )
  }
}

///|
fn dispatch_session(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let verb = need_pos(positions, 1, "session verb")
  match verb {
    "init" => session_init(global)
    "show" => session_show(global)
    "goals" => session_goals(global)
    "end" => session_end(global)
    "report" => session_report(global)
    "scene" => session_scene(global)
    "note" => session_note(global)
    _ =>
      fail(
        TrpgError::Usage(
          "unknown session verb: \{verb}",
          Some("supported verbs: init, show, goals, end, report, scene, note"),
        ),
      )
  }
}

///|
fn session_init(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let scenario_id = need_pos(positions, 2, "scenario_id")
  let db = open_db()
  defer db.close()
  match active_session(db) {
    Some(existing) =>
      if flag_present(global.args, "--if-not-exists") {
        let json = session_json(existing)
        json_success(
          json,
          "既存セッションを再利用: \{existing.scenario_id}",
          global,
        )
      } else {
        fail(
          TrpgError::Conflict(
            "active session already exists",
            Some("run `trpg session end` or pass `--if-not-exists`"),
          ),
        )
      }
    None => {
      let scenario = load_scenario_json(scenario_id)
      validate_scenario_json(scenario, scenario_id)
      let opening = json_string_field(scenario, "opening_scene", "entrance")
      let started = now_ms()
      execute_bound(
        db,
        "INSERT INTO sessions (scenario_id, started_at_ms, current_scene, is_active, ended_at_ms, outcome) VALUES (?, ?, ?, 1, NULL, NULL)",
        [text_value(scenario_id), int64_value(started), text_value(opening)],
      )
      let session_id = db.last_insert_rowid().to_int()
      insert_scenario_scenes(db, session_id, scenario)
      insert_scenario_npcs(db, session_id, scenario)
      let session = SessionRow::{
        id: session_id,
        scenario_id,
        started_at_ms: started,
        current_scene: opening,
        is_active: true,
        ended_at_ms: None,
        outcome: None,
      }
      json_success(
        session_json(session),
        "セッション開始: \{scenario_id} / scene=\{opening}",
        global,
      )
    }
  }
}

///|
fn session_show(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let scenario = load_scenario_json(session.scenario_id)
  let pcs = list_characters(db, session.id).map(row_to_character_json)
  let json = Json::object({
    "command": "session.show",
    "session": session_json(session),
    "characters": Json::array(pcs),
    "scene": require_scenario_scene(scenario, session.current_scene),
  })
  json_success(
    json,
    "active session: \{session.scenario_id} scene=\{session.current_scene}",
    global,
  )
}

///|
fn session_end(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let scenario = load_scenario_json(session.scenario_id)
  let goals = goal_statuses(db, session, scenario)
  let outcome = match option_value(global.args, "--outcome") {
    Some(value) => value
    None => derive_session_outcome(goals)
  }
  let ended = now_ms()
  execute_bound(
    db,
    "UPDATE sessions SET is_active = 0, ended_at_ms = ?, outcome = ? WHERE id = ?",
    [int64_value(ended), text_value(outcome), int_value(session.id)],
  )
  let event_data = Json::object({
    "outcome": Json::string(outcome),
    "goals": Json::array(
      goals.map(goal => {
        Json::object({
          "id": Json::string(goal.id),
          "outcome": Json::string(goal.outcome),
          "satisfied": Json::boolean(goal.satisfied),
          "summary": Json::string(goal.summary),
        })
      }),
    ),
  })
  let event_id = append_event(
    db,
    session.id,
    "session",
    Some("gm"),
    None,
    "session end: \{outcome}",
    event_data.stringify(),
  )
  let json = Json::object({
    "command": "session.end",
    "session_id": j_int(session.id),
    "scenario_id": Json::string(session.scenario_id),
    "outcome": Json::string(outcome),
    "event_id": j_int(event_id),
    "goals": Json::array(goals.map(goal_status_json)),
    "active": false,
  })
  json_success(
    json,
    "セッション終了: \{session.scenario_id} / outcome=\{outcome}",
    global,
  )
}

///|
fn session_goals(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let scenario = load_scenario_json(session.scenario_id)
  let goals = goal_statuses(db, session, scenario)
  let derived_outcome = derive_session_outcome(goals)
  let json = Json::object({
    "command": "session.goals",
    "session": session_json(session),
    "derived_outcome": Json::string(derived_outcome),
    "goals": Json::array(goals.map(goal_status_json)),
  })
  let human = "session: \{session.scenario_id}\n" +
    "scene: \{session.current_scene}\n" +
    "derived_outcome: \{derived_outcome}\n\n" +
    "## goals\n" +
    format_goal_statuses(goals)
  output_success(
    { json, human, stderr: "session.goals: \{session.scenario_id}" },
    global,
  )
}

///|
fn session_report(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let db = open_db()
  defer db.close()
  let session = match active_session(db) {
    Some(value) => value
    None =>
      match latest_session(db) {
        Some(value) => value
        None =>
          fail(
            TrpgError::NotFound(
              "session is not found",
              Some("run `trpg session init forgotten_library` first"),
            ),
          )
      }
  }
  let scenario = load_scenario_json(session.scenario_id)
  let goals = goal_statuses(db, session, scenario)
  let outcome = session.outcome.unwrap_or(derive_session_outcome(goals))
  let characters = list_characters(db, session.id)
  let events = list_events(db, session.id, None, None, 200)
  let key_events = events.filter(event => {
    match event.kind {
      "roll" | "contest" | "attack" | "scene" | "item" | "hp" => true
      _ => false
    }
  })
  let key_event_lines = if key_events.length() == 0 {
    "(なし)"
  } else {
    key_events.map(event => "- \{event.text}").join("\n")
  }
  let character_lines = if characters.length() == 0 {
    "(未登録)"
  } else {
    characters
    .map(row => {
      let items = inventory_from_sheet_json(row.sheet_json) catch { _ => [] }
      let items_text = items.join(", ")
      "- \{row.name} [\{row.kind}] HP \{row.hp_cur}/\{row.hp_max} items=\{items_text} conditions=\{row.conditions_json}"
    })
    .join("\n")
  }
  let goal_lines = format_goal_statuses(goals)
  let human = "session: \{session.scenario_id}\n" +
    "outcome: \{outcome}\n" +
    "scene: \{session.current_scene}\n\n" +
    "## goals\n" +
    goal_lines +
    "\n\n## characters\n" +
    character_lines +
    "\n\n## key events\n" +
    key_event_lines
  let json = Json::object({
    "command": "session.report",
    "session": session_json(session),
    "outcome": Json::string(outcome),
    "goals": Json::array(goals.map(goal_status_json)),
    "characters": Json::array(characters.map(row_to_character_json)),
    "events": Json::array(
      key_events.map(event => {
        Json::object({
          "id": j_int(event.id),
          "kind": Json::string(event.kind),
          "text": Json::string(event.text),
          "created_at_ms": j_i64(event.created_at_ms),
        })
      }),
    ),
  })
  output_success(
    { json, human, stderr: "session.report: \{session.scenario_id}" },
    global,
  )
}

///|
fn session_scene(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let key = need_pos(positions, 2, "scene key")
  let note = option_value(global.args, "--note")
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  set_session_scene(db, session, key, note, global)
}

///|
fn session_note(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let text = need_pos(positions, 2, "note text")
  let note_kind = option_value(global.args, "--kind").unwrap_or("note")
  let ref_event_id = match option_value(global.args, "--ref-event") {
    Some(value) => Some(parse_int_arg(value, "ref-event"))
    None => None
  }
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let id = append_log(db, session.id, "gm", text)
  let event_text = match ref_event_id {
    Some(value) => "gm note[\{note_kind}] ref=\{value}: \{text}"
    None => "gm note[\{note_kind}]: \{text}"
  }
  let event_id = append_event(
    db,
    session.id,
    "note",
    Some("gm"),
    None,
    event_text,
    Json::object({
      "text": Json::string(text),
      "note_kind": Json::string(note_kind),
      "ref_event_id": match ref_event_id {
        Some(value) => j_int(value)
        None => Json::null()
      },
    }).stringify(),
  )
  let json : Map[String, Json] = {
    "command": "session.note",
    "log_id": j_int(id),
    "event_id": j_int(event_id),
    "session_id": j_int(session.id),
    "text": Json::string(text),
    "kind": Json::string(note_kind),
  }
  match ref_event_id {
    Some(value) => json["ref_event_id"] = j_int(value)
    None => ()
  }
  let human = match ref_event_id {
    Some(value) => "note[\{id}] [\{note_kind}] ref=\{value} \{text}"
    None => "note[\{id}] [\{note_kind}] \{text}"
  }
  json_success(Json::object(json), human, global)
}

///|
fn session_json(session : SessionRow) -> Json {
  let object : Map[String, Json] = {
    "id": j_int(session.id),
    "scenario_id": Json::string(session.scenario_id),
    "started_at_ms": j_i64(session.started_at_ms),
    "current_scene": Json::string(session.current_scene),
    "active": Json::boolean(session.is_active),
  }
  match session.ended_at_ms {
    Some(value) => object["ended_at_ms"] = j_i64(value)
    None => ()
  }
  match session.outcome {
    Some(value) => object["outcome"] = Json::string(value)
    None => ()
  }
  Json::object(object)
}

///|
fn set_session_scene(
  db : @sqlite.Database,
  session : SessionRow,
  key : String,
  note : String?,
  global : GlobalArgs,
) -> RunResult raise TrpgFailure {
  if !scene_exists(db, session.id, key) {
    fail(
      TrpgError::NotFound(
        "scene not found: \{key}",
        Some(
          "use `trpg scenario show \{session.scenario_id}` to inspect scenes",
        ),
      ),
    )
  }
  execute_bound(db, "UPDATE sessions SET current_scene = ? WHERE id = ?", [
    text_value(key),
    int_value(session.id),
  ])
  let scenario = load_scenario_json(session.scenario_id)
  let scene = require_scenario_scene(scenario, key)
  let desc = json_string_field(scene, "description", "")
  let expired_rows = expire_scene_duration_statuses(db, session)
  let scene_data : Map[String, Json] = {
    "scene": Json::string(key),
    "description": Json::string(desc),
    "transitions": Json::array(transition_candidates(scene)),
  }
  match note {
    Some(text) if !text.is_empty() => scene_data["note"] = Json::string(text)
    _ => ()
  }
  match scene_difficulty(scene) {
    Some(value) => scene_data["difficulty"] = value
    None => ()
  }
  let event_text = match note {
    Some(text) if !text.is_empty() =>
      "シーン遷移 -> \{key}: \{text} / \{desc}"
    _ => "シーン遷移 -> \{key}: \{desc}"
  }
  let event_id = append_event(
    db,
    session.id,
    "scene",
    Some("gm"),
    Some(key),
    event_text,
    Json::object(scene_data).stringify(),
  )
  let json : Map[String, Json] = {
    "command": Json::string("session.scene"),
    "session_id": j_int(session.id),
    "current_scene": Json::string(key),
    "event_id": j_int(event_id),
    "scene": scene,
  }
  if expired_rows.length() > 0 {
    json["expired_statuses"] = Json::array(
      expired_rows.map(entry => {
        Json::object({
          "name": Json::string(entry.0),
          "statuses": Json::array(entry.1.map(value => Json::string(value))),
        })
      }),
    )
  }
  match note {
    Some(text) if !text.is_empty() => json["note"] = Json::string(text)
    _ => ()
  }
  let human_base = match note {
    Some(text) if !text.is_empty() => "scene -> \{key} / \{text}\n\{desc}"
    _ => "scene -> \{key}\n\{desc}"
  }
  let human = if expired_rows.length() == 0 {
    human_base
  } else {
    human_base +
    "\nexpired_statuses: " +
    expired_rows.map(entry => entry.0 + "=" + entry.1.join(", ")).join("; ")
  }
  json_success(Json::object(json), human, global)
}

///|
fn expire_scene_duration_statuses(
  db : @sqlite.Database,
  session : SessionRow,
) -> Array[(String, Array[String])] raise TrpgFailure {
  let expired_rows : Array[(String, Array[String])] = []
  for row in list_characters(db, session.id) {
    let (next_conditions, expired_names) = expire_scene_duration_conditions(
      row.conditions_json,
    )
    if expired_names.length() > 0 {
      update_character_conditions(db, row.id, next_conditions)
      ignore(
        append_event(
          db,
          session.id,
          "status",
          Some("gm"),
          Some(row.name),
          "\{row.name}: status expire " +
          expired_names.join(", ") +
          " / scene_end",
          Json::object({
            "operation": Json::string("expire"),
            "reason": Json::string("scene_end"),
            "status_names": Json::array(
              expired_names.map(value => Json::string(value)),
            ),
          }).stringify(),
        ),
      )
      expired_rows.push((row.name, expired_names))
    }
  }
  expired_rows
}

///|
fn insert_scenario_scenes(
  db : @sqlite.Database,
  session_id : Int,
  scenario : Json,
) -> Unit raise TrpgFailure {
  match json_get(scenario, "scenes") {
    Some(Object(scenes)) =>
      for key, value in scenes {
        execute_bound(
          db,
          "INSERT OR REPLACE INTO scenes (session_id, key, state_json, flags_json) VALUES (?, ?, ?, ?)",
          [
            int_value(session_id),
            text_value(key),
            text_value(value.stringify()),
            text_value("{}"),
          ],
        )
      }
    _ => ()
  }
}

///|
fn insert_scenario_npcs(
  db : @sqlite.Database,
  session_id : Int,
  scenario : Json,
) -> Unit raise TrpgFailure {
  match json_get(scenario, "npcs") {
    Some(Array(npcs)) =>
      for npc in npcs {
        let name = json_string_field(npc, "name", "NPC")
        let kind = json_string_field(npc, "kind", "npc")
        let sheet = match json_get(npc, "sheet") {
          Some(value) => value
          None => Json::object({})
        }
        let hp_max = json_int_field(sheet, "hp_max", 8)
        insert_character(db, session_id, name, kind, sheet.stringify(), hp_max)
        |> ignore
      }
    _ => ()
  }
}

///|
fn dispatch_pc(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let verb = need_pos(positions, 1, "pc verb")
  match verb {
    "add" => pc_add(global)
    "show" => pc_show(global)
    "style" => pc_style(global)
    "templates" => pc_templates(global)
    _ =>
      fail(
        TrpgError::Usage(
          "unknown pc verb: \{verb}",
          Some("supported verbs: add, show, style, templates"),
        ),
      )
  }
}

///|
fn pc_add(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let name = need_pos(positions, 2, "pc name")
  let from_path = resolve_pc_template_path(global.args)
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  match find_character(db, session.id, name) {
    Some(_) =>
      fail(
        TrpgError::Conflict(
          "character already exists: \{name}",
          Some("choose another name or end the current session"),
        ),
      )
    None => ()
  }
  let sheet_source = read_text_file(from_path)
  let sheet = parse_json(sheet_source, from_path)
  let sheet_object = match sheet {
    Object(object) => object
    _ =>
      fail(
        TrpgError::Usage(
          "invalid character sheet",
          Some("character sheet must be a JSON object"),
        ),
      )
  }
  sheet_object["name"] = Json::string(name)
  let hp_max = json_int_field(sheet, "hp_max", 8)
  let id = insert_character(
    db,
    session.id,
    name,
    "pc",
    Json::object(sheet_object).stringify(),
    hp_max,
  )
  let row = require_character(db, session.id, name)
  let json = Json::object({
    "command": "pc.add",
    "character_id": j_int(id),
    "character": row_to_character_json(row),
  })
  json_success(json, "PC 登録: \{name} hp=\{hp_max}", global)
}

///|
fn pc_show(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let name = need_pos(positions, 2, "pc name")
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let row = require_character(db, session.id, name)
  match option_value(global.args, "--for-roll") {
    Some(ability) => {
      let tags = parse_tags_csv(option_value(global.args, "--tags"))
      let skip_statuses = parse_skip_statuses(global.args)
      let preview = if skip_statuses.length() == 0 {
        roll_preview(row, ability, tags)
      } else {
        roll_preview_with_skips(row, ability, tags, skip_statuses)
      }
      let json = Json::object({
        "command": "pc.show",
        "character": row_to_character_json(row),
        "roll_preview": roll_preview_json(preview),
      })
      json_success(json, format_roll_preview(row.name, preview), global)
    }
    None => {
      let style_text = match play_style_from_sheet_json(row.sheet_json) {
        Some(style) => " / style=\{style.display_name}[\{style.id}]"
        None => ""
      }
      let json = Json::object({
        "command": "pc.show",
        "character": row_to_character_json(row),
      })
      json_success(
        json,
        "\{row.name}: HP \{row.hp_cur}/\{row.hp_max}\{style_text}",
        global,
      )
    }
  }
}

///|
fn pc_style(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let verb = need_pos(positions, 2, "pc style verb")
  match verb {
    "show" => pc_style_show(global)
    "reroll" => pc_style_reroll(global)
    "set" => pc_style_set(global)
    _ =>
      fail(
        TrpgError::Usage(
          "unknown pc style verb: \{verb}",
          Some("supported verbs: show, reroll, set"),
        ),
      )
  }
}

///|
fn pc_style_show(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let name = need_pos(positions, 3, "pc name")
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let row = require_character(db, session.id, name)
  let style = play_style_from_sheet_json(row.sheet_json)
  let json = Json::object({
    "command": "pc.style.show",
    "name": Json::string(name),
    "play_style": match style {
      Some(value) => play_style_json(value)
      None => Json::null()
    },
  })
  let human = match style {
    Some(value) => "\{name}: \{format_play_style_human(value)}"
    None => "\{name}: play_style=(未設定)"
  }
  json_success(json, human, global)
}

///|
fn pc_style_set(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let name = need_pos(positions, 3, "pc name")
  let style_id = need_pos(positions, 4, "style_id")
  let style = require_catalog_play_style(style_id)
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let row = require_character(db, session.id, name)
  let (updated, assigned) = assign_character_play_style(db, row, style)
  let json = Json::object({
    "command": "pc.style.set",
    "character": row_to_character_json(updated),
    "play_style": play_style_json(assigned),
  })
  json_success(
    json,
    "\{name}: style -> \{format_play_style_human(assigned)}",
    global,
  )
}

///|
fn pc_style_reroll(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let name = need_pos(positions, 3, "pc name")
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let row = require_character(db, session.id, name)
  let next_style = rerolled_play_style(
    play_style_from_sheet_json(row.sheet_json),
  )
  let (updated, assigned) = assign_character_play_style(db, row, next_style)
  let json = Json::object({
    "command": "pc.style.reroll",
    "character": row_to_character_json(updated),
    "play_style": play_style_json(assigned),
  })
  json_success(
    json,
    "\{name}: style reroll -> \{format_play_style_human(assigned)}",
    global,
  )
}

///|
fn resolve_pc_template_path(args : Array[String]) -> String raise TrpgFailure {
  match option_value(args, "--from") {
    Some(path) => path
    None =>
      match option_value(args, "--template") {
        Some(template_id) => scenario_template_path(template_id)
        None =>
          fail(
            TrpgError::Usage(
              "missing --from or --template",
              Some(
                "use `trpg pc add alice --from path.json` or `trpg pc add alice --template alice`",
              ),
            ),
          )
      }
  }
}

///|
fn scenario_template_path(template_id : String) -> String raise TrpgFailure {
  let path = scenarios_dir() + "/sample_pc_\{template_id}.json"
  if @fs.path_exists(path) {
    path
  } else {
    fail(
      TrpgError::NotFound(
        "template not found: \{template_id}",
        Some("run `trpg pc templates list` to inspect available templates"),
      ),
    )
  }
}

///|
fn pc_templates(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let verb = need_pos(positions, 2, "templates verb")
  match verb {
    "list" => pc_templates_list(global)
    _ =>
      fail(
        TrpgError::Usage(
          "unknown templates verb: \{verb}",
          Some("supported verbs: list"),
        ),
      )
  }
}

///|
fn pc_templates_list(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let directory = scenarios_dir()
  let entries = @fs.read_dir(directory) catch {
    err =>
      fail(
        TrpgError::NotFound(
          "failed to read scenarios directory",
          Some(err.to_string()),
        ),
      )
  }
  let templates = entries
    .filter(name => name.has_prefix("sample_pc_") && name.has_suffix(".json"))
    .map(name => {
      let template_id = name[10:name.length() - 5].to_string()
      Json::object({
        "id": Json::string(template_id),
        "path": Json::string(directory + "/" + name),
      })
    })
  let human = if templates.length() == 0 {
    "(なし)"
  } else {
    templates
    .map(template => {
      let template_id = json_string_field(template, "id", "")
      let path = json_string_field(template, "path", "")
      "- \{template_id}: \{path}"
    })
    .join("\n")
  }
  output_success(
    {
      json: Json::object({
        "command": "pc.templates.list",
        "templates": Json::array(templates),
      }),
      human,
      stderr: "pc.templates.list",
    },
    global,
  )
}

///|
fn dispatch_roll(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let verb_or_expr = need_pos(positions, 1, "roll expression or subcommand")
  if verb_or_expr == "history" {
    roll_history(global)
  } else if flag_present(global.args, "--preview") &&
    option_value(global.args, "--stat") == None &&
    !flag_present(global.args, "--scene-default") &&
    !flag_present(global.args, "--prep") {
    fail(
      TrpgError::Usage(
        "roll --preview requires character roll options",
        Some("use `trpg roll alice --preview --stat tech --scene-default`"),
      ),
    )
  } else if option_value(global.args, "--stat") != None ||
    flag_present(global.args, "--preview") ||
    flag_present(global.args, "--scene-default") ||
    flag_present(global.args, "--prep") ||
    option_value(global.args, "--grant") != None ||
    option_value(global.args, "--grant-to") != None ||
    option_value(global.args, "--skip-status") != None {
    character_roll(global)
  } else {
    raw_roll(global)
  }
}

///|
fn raw_roll(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let expr = need_pos(positions, 1, "dice expression")
  let target = match option_value(global.args, "--target") {
    Some(value) => Some(parse_int_arg(value, "target"))
    None => None
  }
  let rolled_by = option_value(global.args, "--as")
  let context = option_value(global.args, "--context")
  let roll = eval_dice(expr)
  let outcome = roll_outcome(roll.total, target)
  let margin = roll_margin(roll.total, target)
  let special = roll_special(roll.rolls)
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let roll_id = insert_roll_record(
    db,
    session.id,
    expr,
    roll.total,
    roll.rolls,
    roll.mod,
    target,
    outcome,
    rolled_by,
    context,
  )
  let actor = rolled_by.unwrap_or("gm")
  let event_text = roll_event_text(
    actor,
    expr,
    roll.total,
    target,
    outcome,
    margin,
    special,
    [],
    context,
  )
  let event_id = append_event(
    db,
    session.id,
    "roll",
    Some(actor),
    None,
    event_text,
    Json::object({
      "mode": Json::string("raw"),
      "expr": Json::string(expr),
      "total": j_int(roll.total),
      "rolls": json_int_array(roll.rolls),
      "total_modifier": j_int(roll.mod),
      "modifier_total": j_int(roll.mod),
      "target": match target {
        Some(v) => j_int(v)
        None => Json::null()
      },
      "outcome": Json::string(outcome),
      "margin": match margin {
        Some(v) => j_int(v)
        None => Json::null()
      },
      "special": Json::string(special),
    }).stringify(),
  )
  let json = Json::object({
    "command": "roll",
    "mode": Json::string("raw"),
    "expr": Json::string(expr),
    "total": j_int(roll.total),
    "rolls": json_int_array(roll.rolls),
    "mod": j_int(roll.mod),
    "total_modifier": j_int(roll.mod),
    "target": match target {
      Some(v) => j_int(v)
      None => Json::null()
    },
    "outcome": Json::string(outcome),
    "margin": match margin {
      Some(v) => j_int(v)
      None => Json::null()
    },
    "special": Json::string(special),
    "roll_id": j_int(roll_id),
    "event_id": j_int(event_id),
  })
  let target_text = match target {
    Some(v) => " (target \{v} -> \{outcome})"
    None => ""
  }
  let margin_text = match margin {
    Some(v) => " / margin=\{v}"
    None => ""
  }
  let special_text = if special == "none" {
    ""
  } else {
    " / special=\{special}"
  }
  json_success(
    json,
    "\{expr} = \{roll.breakdown} = \{roll.total}\{target_text}\{margin_text}\{special_text}",
    global,
  )
}

///|
fn prep_target(default_target : Int?) -> Int {
  match default_target {
    Some(value) => if value <= 2 { 2 } else { value - 2 }
    None => 9
  }
}

///|
fn modifier_spec_text(ability : String, amount : Int) -> String {
  if amount >= 0 {
    "\{ability}:+\{amount}"
  } else {
    "\{ability}:\{amount}"
  }
}

///|
fn default_grant_name(actor : String) -> String {
  actor + " の援護"
}

///|
fn parse_skip_statuses(args : Array[String]) -> Array[String] {
  parse_tags_csv(option_value(args, "--skip-status"))
}

///|
fn normalize_grant_on_trigger(value : String) -> String raise TrpgFailure {
  match value {
    "consume" | "persist" => value
    _ =>
      fail(
        TrpgError::Usage(
          "unknown --grant-on-trigger value: \{value}",
          Some("supported values: consume, persist"),
        ),
      )
  }
}

///|
fn grant_status_json(row : GrantedStatusRow) -> Json {
  let object : Map[String, Json] = {
    "target": Json::string(row.target),
    "name": Json::string(row.name),
    "ability": Json::string(row.ability),
    "amount": j_int(row.amount),
    "tags": Json::array(row.tags.map(value => Json::string(value))),
    "uses": j_int(row.uses),
    "on_trigger": Json::string(row.on_trigger),
  }
  match row.source {
    Some(value) => object["source"] = Json::string(value)
    None => ()
  }
  match row.duration {
    Some(value) => object["duration"] = Json::string(value)
    None => object["duration"] = Json::null()
  }
  Json::object(object)
}

///|
fn format_granted_status(row : GrantedStatusRow) -> String {
  let amount_text = if row.amount >= 0 {
    "+" + row.amount.to_string()
  } else {
    row.amount.to_string()
  }
  let tags_text = if row.tags.length() == 0 {
    "(none)"
  } else {
    row.tags.join(",")
  }
  let source_text = match row.source {
    Some(value) if !value.is_empty() => " / source=\{value}"
    _ => ""
  }
  let duration_text = match row.duration {
    Some(value) if !value.is_empty() => " / duration=\{value}"
    _ => ""
  }
  "\{row.target} <= \{row.name} (\{row.ability} \{amount_text} / tags=\{tags_text} / uses=\{row.uses} / on_trigger=\{row.on_trigger}\{duration_text}\{source_text})"
}

///|
fn resolve_grant_status(
  db : @sqlite.Database,
  session_id : Int,
  actor : String,
  args : Array[String],
) -> (CharacterRow, GrantedStatusRow)? raise TrpgFailure {
  let target_name = option_value(args, "--grant-to")
  let spec = option_value(args, "--grant")
  let explicit_name = option_value(args, "--grant-name")
  let grant_uses = match option_value(args, "--grant-uses") {
    Some(value) => parse_int_arg(value, "grant-uses")
    None => 1
  }
  if grant_uses <= 0 {
    fail(
      TrpgError::Usage(
        "grant-uses must be positive",
        Some("use `--grant-uses 1` or larger"),
      ),
    )
  }
  let grant_duration = option_value(args, "--grant-duration")
  let grant_on_trigger = match option_value(args, "--grant-on-trigger") {
    Some(value) => normalize_grant_on_trigger(value)
    None => "consume"
  }
  match (target_name, spec) {
    (None, None) =>
      if explicit_name != None ||
        option_value(args, "--grant-uses") != None ||
        option_value(args, "--grant-duration") != None ||
        option_value(args, "--grant-on-trigger") != None {
        fail(
          TrpgError::Usage(
            "grant options require both --grant and --grant-to",
            Some(
              "use `trpg roll orion --prep --grant-to alice --grant tech:+1@ritual,seal --grant-name 譜面援護 --grant-uses 1 --grant-on-trigger consume`",
            ),
          ),
        )
      } else {
        None
      }
    (Some(_), None) | (None, Some(_)) =>
      fail(
        TrpgError::Usage(
          "granting support requires both --grant-to and --grant",
          Some(
            "use `trpg roll orion --prep --grant-to alice --grant tech:+1@ritual,seal`",
          ),
        ),
      )
    (Some(target), Some(grant_spec)) => {
      let target_row = require_character(db, session_id, target)
      let (ability, amount, grant_tags) = parse_modifier_with_tags_spec(
        grant_spec,
      )
      let granted = {
        target,
        name: explicit_name.unwrap_or(default_grant_name(actor)),
        ability,
        amount,
        tags: grant_tags,
        source: Some(actor),
        uses: grant_uses,
        duration: grant_duration,
        on_trigger: grant_on_trigger,
      }
      Some((target_row, granted))
    }
  }
}

///|
fn apply_granted_status(
  db : @sqlite.Database,
  session : SessionRow,
  row : CharacterRow,
  granted : GrantedStatusRow,
) -> Int raise TrpgFailure {
  let modifier = modifier_spec_text(granted.ability, granted.amount)
  let next_conditions = add_condition(
    row.conditions_json,
    granted.name,
    "",
    Some(modifier),
    Some(granted.uses),
    granted.duration,
    Some(granted.on_trigger),
    granted.tags,
    granted.source,
  )
  update_character_conditions(db, row.id, next_conditions)
  let source_text = match granted.source {
    Some(value) if !value.is_empty() => " / source=\{value}"
    _ => ""
  }
  append_event(
    db,
    session.id,
    "status",
    granted.source,
    Some(granted.target),
    "\{granted.target}: status add \{granted.name}\{source_text}",
    Json::object({
      "operation": Json::string("add"),
      "status_name": Json::string(granted.name),
      "source": match granted.source {
        Some(value) => Json::string(value)
        None => Json::null()
      },
      "auto_granted": Json::boolean(true),
      "effects": Json::array([
        effect_json(granted.ability, granted.amount, granted.tags, "roll"),
      ]),
      "uses": j_int(granted.uses),
      "duration": match granted.duration {
        Some(value) => Json::string(value)
        None => Json::null()
      },
      "on_trigger": Json::string(granted.on_trigger),
      "target": Json::string(granted.target),
    }).stringify(),
  )
}

///|
fn character_roll_preview_json(
  actor : String,
  preview : RollPreview,
  bonus : Int,
  target : Int?,
  tags : Array[String],
  scene_modifiers : Array[SceneModifierRow],
  scene_target_modifier : Int,
  scene_warning : String?,
  skipped_statuses : Array[String],
  grant_plan : (CharacterRow, GrantedStatusRow)?,
) -> Json {
  let object : Map[String, Json] = {
    "command": Json::string("roll"),
    "mode": Json::string("character"),
    "preview": Json::boolean(true),
    "actor": Json::string(actor),
    "ability": Json::string(preview.ability),
    "base_stat": j_int(preview.base_stat),
    "auto_modifier_total": j_int(preview.auto_total),
    "bonus": j_int(bonus),
    "total_modifier": j_int(preview.base_stat + preview.auto_total + bonus),
    "modifier_total": j_int(preview.base_stat + preview.auto_total + bonus),
    "target": match target {
      Some(value) => j_int(value)
      None => Json::null()
    },
    "tags": Json::array(tags.map(value => Json::string(value))),
    "sources": Json::array(preview.modifiers.map(modifier_preview_json)),
    "skipped_sources": Json::array(
      preview.skipped_modifiers.map(skipped_modifier_json),
    ),
    "scene_modifiers": Json::array(scene_modifiers.map(scene_modifier_json)),
    "scene_target_modifier": j_int(scene_target_modifier),
    "inventory": Json::array(
      preview.inventory.map(value => Json::string(value)),
    ),
    "skip_statuses": Json::array(
      skipped_statuses.map(value => Json::string(value)),
    ),
  }
  match scene_warning {
    Some(value) => object["scene_warning"] = Json::string(value)
    None => ()
  }
  match grant_plan {
    Some((_, granted)) => object["grant_plan"] = grant_status_json(granted)
    None => ()
  }
  Json::object(object)
}

///|
fn format_character_roll_preview(
  actor : String,
  preview : RollPreview,
  bonus : Int,
  target : Int?,
  tags : Array[String],
  scene_modifiers : Array[SceneModifierRow],
  scene_target_modifier : Int,
  skipped_statuses : Array[String],
  grant_plan : (CharacterRow, GrantedStatusRow)?,
) -> String {
  let bonus_text = if bonus >= 0 {
    "+" + bonus.to_string()
  } else {
    bonus.to_string()
  }
  let target_text = match target {
    Some(value) => value.to_string()
    None => "(なし)"
  }
  let tags_text = if tags.length() == 0 { "(なし)" } else { tags.join(",") }
  let scene_modifier_text = if scene_modifiers.length() == 0 {
    "(なし)"
  } else {
    "- " + scene_modifiers.map(format_scene_modifier).join("\n- ")
  }
  let skip_text = if skipped_statuses.length() == 0 {
    "(なし)"
  } else {
    skipped_statuses.join(", ")
  }
  let grant_text = match grant_plan {
    Some((_, granted)) => format_granted_status(granted)
    None => "(なし)"
  }
  format_roll_preview(actor, preview) +
  "\nボーナス: \{bonus_text}" +
  "\n想定合計(能力値+自動修正+ボーナス): \{preview.base_stat + preview.auto_total + bonus}" +
  "\ntarget: \{target_text}" +
  "\ntags: \{tags_text}" +
  "\n明示除外 status: \{skip_text}" +
  "\nscene_modifiers:\n" +
  scene_modifier_text +
  "\nscene target 補正合計: \{scene_target_modifier}" +
  "\ngrant_plan: \{grant_text}"
}

///|
fn ensure_resolved_actor_roll_target(
  target : Int?,
  preview_only : Bool,
) -> Unit raise TrpgFailure {
  if !preview_only && target == None {
    fail(
      TrpgError::Usage(
        "actor-aware roll requires a resolved target",
        Some("use `--scene-default`, `--prep`, or `--target N` before rolling"),
      ),
    )
  }
}

///|
fn character_roll(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let actor = need_pos(positions, 1, "actor name")
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let row = require_character(db, session.id, actor)
  let grant_plan = resolve_grant_status(db, session.id, actor, global.args)
  let scenario = load_scenario_json(session.scenario_id)
  let current_scene = require_scenario_scene(scenario, session.current_scene)
  let scene_default = flag_present(global.args, "--scene-default")
  let prep = flag_present(global.args, "--prep")
  let preview_only = flag_present(global.args, "--preview")
  let skip_statuses = parse_skip_statuses(global.args)
  let scene_tags = if scene_default {
    scene_difficulty_tags(current_scene)
  } else {
    []
  }
  let user_tags = parse_tags_csv(option_value(global.args, "--tags"))
  let tag_candidates : Array[String] = []
  for tag in scene_tags {
    tag_candidates.push(tag)
  }
  for tag in user_tags {
    tag_candidates.push(tag)
  }
  let tags = unique_strings(tag_candidates)
  let ability = match option_value(global.args, "--stat") {
    Some(value) => normalize_ability(value)
    None =>
      if scene_default {
        match scene_difficulty_stat(current_scene) {
          Some(value) => normalize_ability(value)
          None =>
            fail(
              TrpgError::Usage(
                "current scene has no default difficulty stat",
                Some("set `difficulty.stat` in the scenario or pass --stat"),
              ),
            )
        }
      } else {
        fail(
          TrpgError::Usage(
            "missing --stat",
            Some("use `trpg roll alice --stat tech --target 9`"),
          ),
        )
      }
  }
  let base_target = match option_value(global.args, "--target") {
    Some(value) => Some(parse_int_arg(value, "target"))
    None =>
      if prep {
        Some(prep_target(scene_difficulty_target(current_scene)))
      } else if scene_default {
        scene_difficulty_target(current_scene)
      } else {
        None
      }
  }
  let no_consume = flag_present(global.args, "--no-consume")
  let scene_modifiers = load_scene_modifiers(
    db,
    session.id,
    session.current_scene,
  )
  let (
    target,
    scene_target_modifier,
    applied_scene_modifiers,
    remaining_scene_modifiers,
  ) = apply_scene_modifiers(scene_modifiers, ability, tags, base_target)
  ensure_resolved_actor_roll_target(target, preview_only)
  let scene_warning : String? = None
  let bonus = match option_value(global.args, "--bonus") {
    Some(value) => parse_int_arg(value, "bonus")
    None => 0
  }
  let preview = roll_preview_with_skips(row, ability, tags, skip_statuses)
  if preview_only {
    let json = character_roll_preview_json(
      actor, preview, bonus, target, tags, applied_scene_modifiers, scene_target_modifier,
      scene_warning, skip_statuses, grant_plan,
    )
    let human = format_character_roll_preview(
      actor, preview, bonus, target, tags, applied_scene_modifiers, scene_target_modifier,
      skip_statuses, grant_plan,
    )
    json_success(json, human, global)
  } else {
    let context = option_value(global.args, "--context")
    let resolved = actor_roll_with_skips(
      row, ability, bonus, target, tags, applied_scene_modifiers, scene_target_modifier,
      scene_warning, skip_statuses,
    )
    if !no_consume && applied_scene_modifiers.length() > 0 {
      save_scene_modifiers(
        db,
        session.id,
        session.current_scene,
        remaining_scene_modifiers,
      )
    }
    if !no_consume && resolved.consumed_statuses.length() > 0 {
      let next_conditions = consume_statuses_json(
        row.conditions_json,
        resolved.consumed_statuses,
      )
      update_character_conditions(db, row.id, next_conditions)
    }
    let granted_status = match grant_plan {
      Some((_, granted)) if resolved.outcome == "HIT" => {
        let target_row = require_character(db, session.id, granted.target)
        ignore(apply_granted_status(db, session, target_row, granted))
        Some(granted)
      }
      _ => None
    }
    let roll_id = insert_roll_record(
      db,
      session.id,
      resolved.expr,
      resolved.total,
      resolved.rolls,
      resolved.total_modifier,
      target,
      resolved.outcome,
      Some(actor),
      context,
    )
    let event_text_base = roll_event_text(
      actor,
      resolved.expr,
      resolved.total,
      target,
      resolved.outcome,
      resolved.margin,
      resolved.special,
      applied_scene_modifiers,
      context,
    )
    let event_text = event_text_base
    let event_data : Map[String, Json] = {
      "command": Json::string("roll"),
      "mode": Json::string("character"),
      "tags": Json::array(tags.map(value => Json::string(value))),
      "roll_id": j_int(roll_id),
    }
    match actor_roll_json(resolved) {
      Object(object) =>
        for key, value in object {
          event_data[key] = value
        }
      _ => ()
    }
    if applied_scene_modifiers.length() > 0 {
      event_data["scene_target_modifier"] = j_int(scene_target_modifier)
      event_data["scene_modifiers"] = Json::array(
        applied_scene_modifiers.map(scene_modifier_json),
      )
    }
    match granted_status {
      Some(value) => event_data["granted_status"] = grant_status_json(value)
      None => ()
    }
    let event_id = append_event(
      db,
      session.id,
      "roll",
      Some(actor),
      Some(ability),
      event_text,
      Json::object(event_data).stringify(),
    )
    let json : Map[String, Json] = {
      "command": Json::string("roll"),
      "mode": Json::string("character"),
      "roll_id": j_int(roll_id),
      "event_id": j_int(event_id),
      "tags": Json::array(tags.map(value => Json::string(value))),
    }
    match actor_roll_json(resolved) {
      Object(object) =>
        for key, value in object {
          json[key] = value
        }
      _ => ()
    }
    if applied_scene_modifiers.length() > 0 {
      json["scene_target_modifier"] = j_int(scene_target_modifier)
      json["scene_modifiers"] = Json::array(
        applied_scene_modifiers.map(scene_modifier_json),
      )
    }
    match granted_status {
      Some(value) => json["granted_status"] = grant_status_json(value)
      None => ()
    }
    match context {
      Some(value) => json["context"] = Json::string(value)
      None => ()
    }
    let human = match granted_status {
      Some(value) =>
        format_actor_roll(resolved) +
        "\ngranted_status: " +
        format_granted_status(value)
      None => format_actor_roll(resolved)
    }
    json_success(Json::object(json), human, global)
  }
}

///|
fn insert_roll_record(
  db : @sqlite.Database,
  session_id : Int,
  expr : String,
  total : Int,
  rolls : Array[Int],
  mod : Int,
  target : Int?,
  outcome : String,
  rolled_by : String?,
  context : String?,
) -> Int raise TrpgFailure {
  let rolls_json = json_int_array(rolls).stringify()
  execute_bound(
    db,
    "INSERT INTO rolls (session_id, expr, total, rolls_json, mod, target, outcome, rolled_by, context, created_at_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    [
      int_value(session_id),
      text_value(expr),
      int_value(total),
      text_value(rolls_json),
      int_value(mod),
      match target {
        Some(v) => int_value(v)
        None => @sqlite.SqlValue::Null
      },
      text_value(outcome),
      match rolled_by {
        Some(v) => text_value(v)
        None => @sqlite.SqlValue::Null
      },
      match context {
        Some(v) => text_value(v)
        None => @sqlite.SqlValue::Null
      },
      int64_value(now_ms()),
    ],
  )
  db.last_insert_rowid().to_int()
}

///|
fn roll_event_text(
  actor : String,
  expr : String,
  total : Int,
  target : Int?,
  outcome : String,
  margin : Int?,
  special : String,
  scene_modifiers : Array[SceneModifierRow],
  context : String?,
) -> String {
  let target_text = match target {
    Some(value) => " / target=\{value}"
    None => ""
  }
  let margin_text = match margin {
    Some(value) => " / margin=\{value}"
    None => ""
  }
  let special_text = if special == "none" {
    ""
  } else {
    " / special=\{special}"
  }
  let modifier_text = if scene_modifiers.length() == 0 {
    ""
  } else {
    " / scene_modifiers=" +
    scene_modifiers.map(modifier => modifier.name).join(", ")
  }
  let context_text = match context {
    Some(value) if !value.is_empty() => " / \{value}"
    _ => ""
  }
  "判定 \{actor}: \{expr} = \{total}\{target_text} / \{outcome}\{margin_text}\{special_text}\{modifier_text}\{context_text}"
}

///|
fn roll_history(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let limit = match option_value(global.args, "-n") {
    Some(value) => parse_int_arg(value, "limit")
    None => 20
  }
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let actor = option_value(global.args, "--as")
  let events = list_events(db, session.id, Some("roll"), actor, limit)
  let json = Json::object({
    "command": "roll.history",
    "events": Json::array(
      events.map(event => {
        Json::object({
          "id": j_int(event.id),
          "actor": match event.actor {
            Some(value) => Json::string(value)
            None => Json::null()
          },
          "text": Json::string(event.text),
          "created_at_ms": j_i64(event.created_at_ms),
          "data": parse_json(event.data_json, "events.data_json"),
        })
      }),
    ),
  })
  let human = if events.length() == 0 {
    "(なし)"
  } else {
    events.map(event => "- \{event.text}").join("\n")
  }
  output_success({ json, human, stderr: "roll.history" }, global)
}

///|
fn dispatch_hp(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let name = need_pos(positions, 1, "character name")
  let delta = parse_int_arg(need_pos(positions, 2, "hp delta"), "hp delta")
  let actor = option_value(global.args, "--by").unwrap_or("gm")
  let context = option_value(global.args, "--context")
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let row = require_character(db, session.id, name)
  let next = clamp_int(row.hp_cur + delta, 0, row.hp_max)
  execute_bound(db, "UPDATE statuses SET hp_cur = ? WHERE character_id = ?", [
    int_value(next),
    int_value(row.id),
  ])
  let json = Json::object({
    "command": "hp",
    "name": Json::string(name),
    "delta": j_int(delta),
    "hp_cur": j_int(next),
    "hp_max": j_int(row.hp_max),
  })
  let text = match context {
    Some(value) if !value.is_empty() =>
      "\{actor}: \{name} HP \{row.hp_cur} -> \{next} / \{value}"
    _ => "\{actor}: \{name} HP \{row.hp_cur} -> \{next}"
  }
  ignore(
    append_event(
      db,
      session.id,
      "hp",
      Some(actor),
      Some(name),
      text,
      Json::object({
        "delta": j_int(delta),
        "hp_cur": j_int(next),
        "hp_max": j_int(row.hp_max),
        "context": match context {
          Some(value) => Json::string(value)
          None => Json::null()
        },
      }).stringify(),
    ),
  )
  json_success(json, "\{name}: HP \{row.hp_cur} -> \{next}", global)
}

///|
fn clamp_int(value : Int, lo : Int, hi : Int) -> Int {
  if value < lo {
    lo
  } else if value > hi {
    hi
  } else {
    value
  }
}

///|
fn dispatch_status(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let name = need_pos(positions, 1, "character name")
  let op = need_pos(positions, 2, "status operation")
  let note = option_value(global.args, "--note").unwrap_or("")
  let source_name = option_value(global.args, "--source")
  let tags = parse_tags_csv(option_value(global.args, "--tags"))
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let row = require_character(db, session.id, name)
  let status_name = match op {
    "add" =>
      if positions.length() > 3 {
        fail(
          TrpgError::Usage(
            "status add no longer accepts positional status names",
            Some("use `trpg status <character> add --name \"援護名\" ...`"),
          ),
        )
      } else {
        match option_value(global.args, "--name") {
          Some(value) if !value.is_empty() => value
          _ =>
            fail(
              TrpgError::Usage(
                "missing --name for status add",
                Some(
                  "use `trpg status <character> add --name \"援護名\" --modifier tech:+1 ...`",
                ),
              ),
            )
        }
      }
    "remove" => {
      if positions.length() > 4 {
        fail(
          TrpgError::Usage(
            "too many positional arguments for status remove",
            Some("use `trpg status <character> remove <status name>`"),
          ),
        )
      }
      need_pos(positions, 3, "status name")
    }
    _ =>
      fail(
        TrpgError::Usage(
          "unknown status operation: \{op}",
          Some("supported operations: add, remove"),
        ),
      )
  }
  let conditions_json = match op {
    "add" =>
      add_condition(
        row.conditions_json,
        status_name,
        note,
        option_value(global.args, "--modifier"),
        match option_value(global.args, "--uses") {
          Some(value) => Some(parse_int_arg(value, "uses"))
          None => None
        },
        option_value(global.args, "--duration"),
        option_value(global.args, "--on-trigger"),
        tags,
        source_name,
      )
    "remove" => remove_condition(row.conditions_json, status_name)
    _ => row.conditions_json
  }
  update_character_conditions(db, row.id, conditions_json)
  let json = Json::object({
    "command": "status",
    "name": Json::string(name),
    "operation": Json::string(op),
    "status_name": Json::string(status_name),
    "tag": Json::string(status_name),
    "source": match source_name {
      Some(value) => Json::string(value)
      None => Json::null()
    },
    "conditions": parse_json(conditions_json, "conditions_json"),
  })
  let event_text = match source_name {
    Some(value) if op == "add" && !value.is_empty() =>
      "\{name}: status \{op} \{status_name} / source=\{value}"
    _ => "\{name}: status \{op} \{status_name}"
  }
  ignore(
    append_event(
      db,
      session.id,
      "status",
      match source_name {
        Some(value) => Some(value)
        None => Some("gm")
      },
      Some(name),
      event_text,
      Json::object({
        "operation": Json::string(op),
        "status_name": Json::string(status_name),
        "tag": Json::string(status_name),
        "source": match source_name {
          Some(value) => Json::string(value)
          None => Json::null()
        },
        "tags": Json::array(tags.map(value => Json::string(value))),
        "conditions": parse_json(conditions_json, "conditions_json"),
      }).stringify(),
    ),
  )
  json_success(json, "\{name}: status \{op} \{status_name}", global)
}

///|
fn add_condition(
  source : String,
  status_name : String,
  note : String,
  modifier : String?,
  uses : Int?,
  duration : String?,
  on_trigger : String?,
  tags : Array[String],
  source_name : String?,
) -> String raise TrpgFailure {
  let arr = match parse_json(source, "conditions_json") {
    Array(items) => items
    _ => []
  }
  let condition : Map[String, Json] = {
    "name": Json::string(status_name),
    "note": Json::string(note),
    "applied_at_ms": j_i64(now_ms()),
  }
  match modifier {
    Some(value) => {
      let (ability, amount) = parse_modifier_spec(value)
      condition["effects"] = Json::array([
        effect_json(ability, amount, tags, "roll"),
      ])
    }
    None => ()
  }
  match source_name {
    Some(value) if !value.is_empty() =>
      condition["source"] = Json::string(value)
    _ => ()
  }
  match uses {
    Some(value) => condition["uses"] = j_int(value)
    None => ()
  }
  match duration {
    Some(value) if !value.is_empty() =>
      condition["duration"] = Json::string(value)
    _ => ()
  }
  match on_trigger {
    Some(value) if !value.is_empty() =>
      condition["on_trigger"] = Json::string(value)
    _ => ()
  }
  arr.push(Json::object(condition))
  Json::array(arr).stringify()
}

///|
fn remove_condition(source : String, tag : String) -> String raise TrpgFailure {
  let arr = match parse_json(source, "conditions_json") {
    Array(items) => items
    _ => []
  }
  let kept : Array[Json] = []
  for item in arr {
    let keep = match item {
      Object(object) =>
        match object.get("name") {
          Some(String(value)) => value != tag
          _ => true
        }
      _ => true
    }
    if keep {
      kept.push(item)
    }
  }
  Json::array(kept).stringify()
}

///|
fn dispatch_log(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let verb = need_pos(positions, 1, "log verb")
  match verb {
    "add" => log_add(global)
    "tail" => log_tail(global)
    "show" => log_show(global)
    _ =>
      fail(
        TrpgError::Usage(
          "unknown log verb: \{verb}",
          Some("supported verbs: add, tail, show"),
        ),
      )
  }
}

///|
fn log_add(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let text = need_pos(positions, 2, "log text")
  let actor = option_value(global.args, "--as").unwrap_or("gm")
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let id = append_log(db, session.id, actor, text)
  let event_id = append_event(
    db,
    session.id,
    "log",
    Some(actor),
    None,
    "\{actor}: \{text}",
    Json::object({ "text": Json::string(text) }).stringify(),
  )
  let json = Json::object({
    "command": "log.add",
    "log_id": j_int(id),
    "event_id": j_int(event_id),
    "actor": Json::string(actor),
    "text": Json::string(text),
  })
  json_success(json, "log[\{id}] \{actor}: \{text}", global)
}

///|
fn log_tail(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let limit = match option_value(global.args, "-n") {
    Some(value) => parse_int_arg(value, "limit")
    None => 20
  }
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let rows = recent_logs(db, session.id, limit)
  let json_rows = rows.map(row => {
    Json::object({
      "id": j_int(row.id),
      "actor": Json::string(row.actor),
      "text": Json::string(row.text),
      "created_at_ms": j_i64(row.created_at_ms),
    })
  })
  let human = rows
    .map(row => "[\{row.id}] \{row.actor}: \{row.text}")
    .join("\n")
  output_success(
    {
      json: Json::object({
        "command": "log.tail",
        "logs": Json::array(json_rows),
      }),
      human,
      stderr: human,
    },
    global,
  )
}

///|
fn log_show(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let limit = match option_value(global.args, "-n") {
    Some(value) => parse_int_arg(value, "limit")
    None => 20
  }
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let kind = option_value(global.args, "--kind")
  let actor = option_value(global.args, "--by")
  let events = list_events(db, session.id, kind, actor, limit)
  let json = Json::object({
    "command": "log.show",
    "events": Json::array(
      events.map(event => {
        Json::object({
          "id": j_int(event.id),
          "kind": Json::string(event.kind),
          "actor": match event.actor {
            Some(value) => Json::string(value)
            None => Json::null()
          },
          "text": Json::string(event.text),
          "created_at_ms": j_i64(event.created_at_ms),
        })
      }),
    ),
  })
  let human = if events.length() == 0 {
    "(なし)"
  } else {
    events.map(event => "- [\{event.kind}] \{event.text}").join("\n")
  }
  output_success({ json, human, stderr: "log.show" }, global)
}

///|
fn dispatch_item(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let verb = need_pos(positions, 1, "item verb")
  match verb {
    "give" => item_give(global)
    "drop" => item_drop(global)
    "transfer" => item_transfer(global)
    "list" => item_list(global)
    _ =>
      fail(
        TrpgError::Usage(
          "unknown item verb: \{verb}",
          Some("supported verbs: give, drop, transfer, list"),
        ),
      )
  }
}

///|
fn item_give(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let name = need_pos(positions, 2, "character name")
  let item = need_pos(positions, 3, "item name")
  let note = option_value(global.args, "--note")
  let desc = option_value(global.args, "--desc")
  let effect = option_value(global.args, "--effect")
  let tags = parse_tags_csv(option_value(global.args, "--tags"))
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let row = require_character(db, session.id, name)
  let next_sheet = add_inventory_item_json(
    row.sheet_json,
    item,
    desc,
    effect,
    tags,
  )
  update_character_sheet(db, row.id, next_sheet)
  let text = match note {
    Some(value) if !value.is_empty() =>
      "\{name} が \{item} を獲得: \{value}"
    _ => "\{name} が \{item} を獲得"
  }
  let updated = require_character(db, session.id, name)
  let event_id = append_event(
    db,
    session.id,
    "item",
    Some("gm"),
    Some(name),
    text,
    Json::object({
      "operation": Json::string("give"),
      "item": Json::string(item),
      "item_id": Json::string(item),
      "effect": match effect {
        Some(value) => Json::string(value)
        None => Json::null()
      },
      "tags": Json::array(tags.map(value => Json::string(value))),
      "inventory": Json::array(
        inventory_from_sheet_json(updated.sheet_json).map(value => {
          Json::string(value)
        }),
      ),
    }).stringify(),
  )
  let json = Json::object({
    "command": "item.give",
    "name": Json::string(name),
    "item": Json::string(item),
    "event_id": j_int(event_id),
    "inventory": Json::array(
      inventory_from_sheet_json(updated.sheet_json).map(value => {
        Json::string(value)
      }),
    ),
  })
  json_success(json, "\{name}: \{item} を獲得", global)
}

///|
fn item_drop(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let name = need_pos(positions, 2, "character name")
  let item = need_pos(positions, 3, "item name")
  let note = option_value(global.args, "--note")
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let row = require_character(db, session.id, name)
  let next_sheet = drop_inventory_item_json(row.sheet_json, item)
  update_character_sheet(db, row.id, next_sheet)
  let text = match note {
    Some(value) if !value.is_empty() =>
      "\{name} が \{item} を失う: \{value}"
    _ => "\{name} が \{item} を失う"
  }
  let updated = require_character(db, session.id, name)
  let event_id = append_event(
    db,
    session.id,
    "item",
    Some("gm"),
    Some(name),
    text,
    Json::object({
      "operation": Json::string("drop"),
      "item": Json::string(item),
      "item_id": Json::string(item),
      "inventory": Json::array(
        inventory_from_sheet_json(updated.sheet_json).map(value => {
          Json::string(value)
        }),
      ),
    }).stringify(),
  )
  let json = Json::object({
    "command": "item.drop",
    "name": Json::string(name),
    "item": Json::string(item),
    "event_id": j_int(event_id),
    "inventory": Json::array(
      inventory_from_sheet_json(updated.sheet_json).map(value => {
        Json::string(value)
      }),
    ),
  })
  json_success(json, "\{name}: \{item} を失う", global)
}

///|
fn item_transfer(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let from_name = need_pos(positions, 2, "source character name")
  let to_name = need_pos(positions, 3, "target character name")
  let item = need_pos(positions, 4, "item name")
  let note = option_value(global.args, "--note")
  let add_tags = parse_tags_csv(option_value(global.args, "--add-tags"))
  let set_effect = option_value(global.args, "--set-effect")
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let from_row = require_character(db, session.id, from_name)
  let to_row = require_character(db, session.id, to_name)
  let (next_from_sheet, item_json) = take_inventory_item_json(
    from_row.sheet_json,
    item,
  )
  let transferred_item = update_inventory_item_json(
    item_json, add_tags, set_effect,
  )
  let next_to_sheet = add_existing_inventory_item_json(
    to_row.sheet_json,
    transferred_item,
  )
  update_character_sheet(db, from_row.id, next_from_sheet)
  update_character_sheet(db, to_row.id, next_to_sheet)
  let item_name = object_name(transferred_item, item)
  let item_id = json_string_field(transferred_item, "id", item_name)
  let update_text = if add_tags.length() == 0 && set_effect == None {
    ""
  } else {
    let parts : Array[String] = []
    if add_tags.length() > 0 {
      let add_tags_text = add_tags.join(",")
      parts.push("add-tags=\{add_tags_text}")
    }
    match set_effect {
      Some(value) => parts.push("set-effect=\{value}")
      None => ()
    }
    " / " + parts.join(" / ")
  }
  let text = match note {
    Some(value) if !value.is_empty() =>
      "\{from_name} -> \{to_name}: \{item_name} を移譲\{update_text} / \{value}"
    _ => "\{from_name} -> \{to_name}: \{item_name} を移譲\{update_text}"
  }
  let updated_from = require_character(db, session.id, from_name)
  let updated_to = require_character(db, session.id, to_name)
  let event_id = append_event(
    db,
    session.id,
    "item",
    Some("gm"),
    Some(to_name),
    text,
    Json::object({
      "operation": Json::string("transfer"),
      "from": Json::string(from_name),
      "to": Json::string(to_name),
      "item": Json::string(item_name),
      "item_id": Json::string(item_id),
      "item_object": transferred_item,
      "add_tags": Json::array(add_tags.map(value => Json::string(value))),
      "set_effect": match set_effect {
        Some(value) => Json::string(value)
        None => Json::null()
      },
      "from_inventory": Json::array(
        inventory_from_sheet_json(updated_from.sheet_json).map(value => {
          Json::string(value)
        }),
      ),
      "to_inventory": Json::array(
        inventory_from_sheet_json(updated_to.sheet_json).map(value => {
          Json::string(value)
        }),
      ),
    }).stringify(),
  )
  let json = Json::object({
    "command": "item.transfer",
    "from": Json::string(from_name),
    "to": Json::string(to_name),
    "item": Json::string(item_name),
    "item_id": Json::string(item_id),
    "event_id": j_int(event_id),
    "item_object": transferred_item,
    "from_inventory": Json::array(
      inventory_from_sheet_json(updated_from.sheet_json).map(value => {
        Json::string(value)
      }),
    ),
    "to_inventory": Json::array(
      inventory_from_sheet_json(updated_to.sheet_json).map(value => {
        Json::string(value)
      }),
    ),
  })
  json_success(json, text, global)
}

///|
fn item_list(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  match positions.get(2) {
    Some(name) => {
      let row = require_character(db, session.id, name)
      let items = inventory_from_sheet_json(row.sheet_json)
      let json = Json::object({
        "command": "item.list",
        "name": Json::string(name),
        "inventory": Json::array(items.map(value => Json::string(value))),
      })
      let human = if items.length() == 0 {
        "\{name}: (なし)"
      } else {
        "\{name}: " + items.join(", ")
      }
      json_success(json, human, global)
    }
    None => {
      let rows = list_characters(db, session.id)
      let inventory_map : Map[String, Json] = {}
      let human_lines : Array[String] = []
      for row in rows {
        let items = inventory_from_sheet_json(row.sheet_json)
        inventory_map[row.name] = Json::array(
          items.map(value => Json::string(value)),
        )
        let human = if items.length() == 0 {
          "\{row.name}: (なし)"
        } else {
          "\{row.name}: " + items.join(", ")
        }
        human_lines.push(human)
      }
      let json = Json::object({
        "command": "item.list",
        "inventory": Json::object(inventory_map),
      })
      let human = if human_lines.length() == 0 {
        "(未登録)"
      } else {
        human_lines.join("\n")
      }
      json_success(json, human, global)
    }
  }
}

///|
fn dispatch_scene(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let verb = need_pos(positions, 1, "scene verb")
  match verb {
    "set" => scene_set(global)
    "list" => scene_list(global)
    "show" => scene_show(global)
    "next" => scene_next(global)
    "flag" => scene_flag(global)
    "progress" => scene_progress(global)
    "modifier" => scene_modifier(global)
    _ =>
      fail(
        TrpgError::Usage(
          "unknown scene verb: \{verb}",
          Some(
            "supported verbs: set, list, show, next, flag, progress, modifier",
          ),
        ),
      )
  }
}

///|
fn scene_set(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let key = need_pos(positions, 2, "scene key")
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  set_session_scene(
    db,
    session,
    key,
    option_value(global.args, "--note"),
    global,
  )
}

///|
fn scene_flag(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let key = need_pos(positions, 2, "flag key")
  let value = need_pos(positions, 3, "flag value")
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let flags = load_scene_flags(db, session.id, session.current_scene)
  flags[key] = Json::string(value)
  execute_bound(
    db,
    "UPDATE scenes SET flags_json = ? WHERE session_id = ? AND key = ?",
    [
      text_value(Json::object(flags).stringify()),
      int_value(session.id),
      text_value(session.current_scene),
    ],
  )
  let json = Json::object({
    "command": "scene.flag",
    "scene": Json::string(session.current_scene),
    "key": Json::string(key),
    "value": Json::string(value),
    "flags": Json::object(flags),
  })
  ignore(
    append_event(
      db,
      session.id,
      "scene",
      Some("gm"),
      Some(session.current_scene),
      "scene flag \{session.current_scene}.\{key}=\{value}",
      Json::object({
        "scene": Json::string(session.current_scene),
        "flag": Json::string(key),
        "value": Json::string(value),
      }).stringify(),
    ),
  )
  json_success(json, "flag[\{session.current_scene}] \{key}=\{value}", global)
}

///|
fn scene_progress(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let progress_key = need_pos(positions, 2, "progress key")
  let delta = parse_int_arg(
    need_pos(positions, 3, "progress delta"),
    "progress delta",
  )
  let note = option_value(global.args, "--note")
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let current = load_scene_progress(db, session.id, session.current_scene)
  let next_value = match current.get(progress_key) {
    Some(value) => value + delta
    None => delta
  }
  current[progress_key] = next_value
  save_scene_progress(db, session.id, session.current_scene, current)
  let text = match note {
    Some(value) if !value.is_empty() =>
      "progress[\{session.current_scene}] \{progress_key} += \{delta} -> \{next_value} / \{value}"
    _ =>
      "progress[\{session.current_scene}] \{progress_key} += \{delta} -> \{next_value}"
  }
  let event_id = append_event(
    db,
    session.id,
    "scene",
    Some("gm"),
    Some(session.current_scene),
    text,
    Json::object({
      "operation": Json::string("progress"),
      "key": Json::string(progress_key),
      "delta": j_int(delta),
      "value": j_int(next_value),
      "note": match note {
        Some(value) => Json::string(value)
        None => Json::null()
      },
    }).stringify(),
  )
  let json = Json::object({
    "command": "scene.progress",
    "scene": Json::string(session.current_scene),
    "key": Json::string(progress_key),
    "delta": j_int(delta),
    "value": j_int(next_value),
    "event_id": j_int(event_id),
  })
  output_success({ json, human: text, stderr: text }, global)
}

///|
fn scene_modifier(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let verb = need_pos(positions, 2, "scene modifier verb")
  match verb {
    "add" => scene_modifier_add(global)
    _ =>
      fail(
        TrpgError::Usage(
          "unknown scene modifier verb: \{verb}",
          Some("supported verbs: add"),
        ),
      )
  }
}

///|
fn parse_next_roll_target_delta(spec : String) -> Int raise TrpgFailure {
  match spec.split_once(":") {
    Some((kind, value)) =>
      if kind == "target" {
        parse_int_arg(value.to_string(), "target delta")
      } else {
        fail(
          TrpgError::Usage(
            "unsupported --next-roll spec: \{spec}",
            Some("use `--next-roll target:-2`"),
          ),
        )
      }
    None =>
      fail(
        TrpgError::Usage(
          "invalid --next-roll spec: \{spec}",
          Some("use `--next-roll target:-2`"),
        ),
      )
  }
}

///|
fn scene_modifier_add(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let name = match option_value(global.args, "--name") {
    Some(value) if !value.is_empty() => value
    _ =>
      fail(
        TrpgError::Usage(
          "missing --name for scene modifier add",
          Some(
            "use `trpg scene modifier add --name \"扉が緩む\" --next-roll target:-2 --stat tech --tags forced-entry`",
          ),
        ),
      )
  }
  let target_delta = match option_value(global.args, "--next-roll") {
    Some(value) => parse_next_roll_target_delta(value)
    None =>
      fail(
        TrpgError::Usage(
          "missing --next-roll for scene modifier add",
          Some("use `--next-roll target:-2`"),
        ),
      )
  }
  let stat = match option_value(global.args, "--stat") {
    Some(value) => Some(normalize_ability(value))
    None => None
  }
  let tags = parse_tags_csv(option_value(global.args, "--tags"))
  let note = option_value(global.args, "--note").unwrap_or("")
  let source = option_value(global.args, "--source")
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let modifiers = load_scene_modifiers(db, session.id, session.current_scene)
  let row : SceneModifierRow = {
    name,
    target_delta,
    stat,
    tags,
    note,
    source,
    scope: "next_roll",
  }
  modifiers.push(row)
  save_scene_modifiers(db, session.id, session.current_scene, modifiers)
  let text = "scene modifier[\{session.current_scene}] " +
    format_scene_modifier(row)
  let event_id = append_event(
    db,
    session.id,
    "scene",
    Some(source.unwrap_or("gm")),
    Some(session.current_scene),
    text,
    Json::object({
      "operation": Json::string("modifier_add"),
      "scene": Json::string(session.current_scene),
      "modifier": scene_modifier_json(row),
    }).stringify(),
  )
  let json = Json::object({
    "command": "scene.modifier.add",
    "scene": Json::string(session.current_scene),
    "modifier": scene_modifier_json(row),
    "event_id": j_int(event_id),
  })
  output_success({ json, human: text, stderr: text }, global)
}

///|
fn scene_list(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let scenario = load_scenario_json(session.scenario_id)
  let current = session.current_scene
  let scenes = match json_get(scenario, "scenes") {
    Some(Object(object)) => object
    _ => {}
  }
  let transitions = available_scene_transitions(db, session, scenario)
  let human_lines : Array[String] = []
  let scene_rows : Array[Json] = []
  for key, scene in scenes {
    human_lines.push(format_scene_summary(key, scene, key == current))
    scene_rows.push(
      Json::object({
        "key": Json::string(key),
        "current": Json::boolean(key == current),
        "scene": scene,
      }),
    )
  }
  let json = Json::object({
    "command": "scene.list",
    "current_scene": Json::string(current),
    "scenes": Json::array(scene_rows),
    "available_transitions": Json::array(transitions),
  })
  let transitions_text = if transitions.length() == 0 {
    "(なし)"
  } else {
    transitions.map(format_scene_transition).join("\n")
  }
  let human = human_lines.join("\n") + "\n\n遷移候補:\n" + transitions_text
  output_success({ json, human, stderr: "scene.list" }, global)
}

///|
fn scene_show(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let scenario = load_scenario_json(session.scenario_id)
  let key = positions.get(2).unwrap_or(session.current_scene)
  let scene = require_scenario_scene(scenario, key)
  let flags = load_scene_flags(db, session.id, key)
  let progress = load_scene_progress(db, session.id, key)
  let modifiers = load_scene_modifiers(db, session.id, key)
  let transitions = if key == session.current_scene {
    available_scene_transitions(db, session, scenario)
  } else {
    transition_candidates(scene)
  }
  let difficulty_text = match scene_difficulty(scene) {
    Some(info) => {
      let stat = json_string_field(info, "stat", "")
      let target = json_int_field(info, "target", 0)
      "\{stat} \{target}"
    }
    None => "(なし)"
  }
  let transitions_text = if transitions.length() == 0 {
    "(なし)"
  } else {
    transitions.map(format_scene_transition).join("\n")
  }
  let progress_text = if progress.is_empty() {
    "(なし)"
  } else {
    progress
    .iter()
    .map(fn(kv) {
      let (k, v) = kv
      "- \{k}: \{v}"
    })
    .join("\n")
  }
  let modifiers_text = if modifiers.length() == 0 {
    "(なし)"
  } else {
    modifiers.map(row => "- " + format_scene_modifier(row)).join("\n")
  }
  let human = "scene: \{key}\n" +
    json_string_field(scene, "description", "") +
    "\n難易度: \{difficulty_text}\n進捗:\n" +
    progress_text +
    "\nmodifier:\n" +
    modifiers_text +
    "\n遷移:\n" +
    transitions_text
  let progress_json : Map[String, Json] = {}
  for k, v in progress {
    progress_json[k] = j_int(v)
  }
  let json = Json::object({
    "command": "scene.show",
    "key": Json::string(key),
    "current": Json::boolean(key == session.current_scene),
    "scene": scene,
    "flags": Json::object(flags),
    "progress": Json::object(progress_json),
    "modifiers": Json::array(modifiers.map(scene_modifier_json)),
    "available_transitions": Json::array(transitions),
  })
  output_success({ json, human, stderr: "scene.show: \{key}" }, global)
}

///|
fn scene_next(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let scenario = load_scenario_json(session.scenario_id)
  let transitions = available_scene_transitions(db, session, scenario)
  if transitions.length() == 0 {
    fail(
      TrpgError::Conflict(
        "no available transition",
        Some("use `trpg scene list` to inspect current scene state"),
      ),
    )
  }
  if transitions.length() > 1 {
    fail(
      TrpgError::Conflict(
        "multiple transitions are available",
        Some("use `trpg scene list` or `trpg session scene <id>`"),
      ),
    )
  }
  let next_scene = json_string_field(transitions[0], "to", "")
  set_session_scene(
    db,
    session,
    next_scene,
    option_value(global.args, "--note"),
    global,
  )
}

///|
fn load_scene_flags(
  db : @sqlite.Database,
  session_id : Int,
  scene_key : String,
) -> Map[String, Json] raise TrpgFailure {
  let stmt = prepare(
    db, "SELECT flags_json FROM scenes WHERE session_id = ? AND key = ? LIMIT 1",
  )
  stmt.bind_all([int_value(session_id), text_value(scene_key)]) |> ignore
  let flags = if stmt.step() {
    match parse_json(bytes_to_string(stmt.column_text(0)), "flags_json") {
      Object(object) => object
      _ => {}
    }
  } else {
    {}
  }
  finish_statement(stmt)
  flags
}

///|
fn load_scene_progress(
  db : @sqlite.Database,
  session_id : Int,
  scene_key : String,
) -> Map[String, Int] raise TrpgFailure {
  let state = load_scene_state_object(db, session_id, scene_key)
  let progress_object = match state.get("progress") {
    Some(Object(progress_map)) => progress_map
    _ => {}
  }
  let out : Map[String, Int] = {}
  for key, value in progress_object {
    match value {
      Number(number, ..) => out[key] = number.to_int()
      _ => ()
    }
  }
  out
}

///|
fn load_scene_modifiers(
  db : @sqlite.Database,
  session_id : Int,
  scene_key : String,
) -> Array[SceneModifierRow] raise TrpgFailure {
  let state = load_scene_state_object(db, session_id, scene_key)
  match state.get("modifiers") {
    Some(Array(items)) => items.map(scene_modifier_from_json)
    _ => []
  }
}

///|
fn load_scene_state_object(
  db : @sqlite.Database,
  session_id : Int,
  scene_key : String,
) -> Map[String, Json] raise TrpgFailure {
  let stmt = prepare(
    db, "SELECT state_json FROM scenes WHERE session_id = ? AND key = ? LIMIT 1",
  )
  stmt.bind_all([int_value(session_id), text_value(scene_key)]) |> ignore
  let state = if stmt.step() {
    match parse_json(bytes_to_string(stmt.column_text(0)), "state_json") {
      Object(object) => object
      _ => {}
    }
  } else {
    {}
  }
  finish_statement(stmt)
  state
}

///|
fn save_scene_progress(
  db : @sqlite.Database,
  session_id : Int,
  scene_key : String,
  progress : Map[String, Int],
) -> Unit raise TrpgFailure {
  let state = load_scene_state_object(db, session_id, scene_key)
  let progress_json : Map[String, Json] = {}
  for k, v in progress {
    progress_json[k] = j_int(v)
  }
  state["progress"] = Json::object(progress_json)
  save_scene_state_object(db, session_id, scene_key, state)
}

///|
fn save_scene_modifiers(
  db : @sqlite.Database,
  session_id : Int,
  scene_key : String,
  modifiers : Array[SceneModifierRow],
) -> Unit raise TrpgFailure {
  let state = load_scene_state_object(db, session_id, scene_key)
  state["modifiers"] = Json::array(modifiers.map(scene_modifier_json))
  save_scene_state_object(db, session_id, scene_key, state)
}

///|
fn save_scene_state_object(
  db : @sqlite.Database,
  session_id : Int,
  scene_key : String,
  state : Map[String, Json],
) -> Unit raise TrpgFailure {
  execute_bound(
    db,
    "UPDATE scenes SET state_json = ? WHERE session_id = ? AND key = ?",
    [
      text_value(Json::object(state).stringify()),
      int_value(session_id),
      text_value(scene_key),
    ],
  )
}

///|
async fn dispatch_scenario(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let verb = need_pos(positions, 1, "scenario verb")
  match verb {
    "list" => scenario_list(global)
    "import" => scenario_import(global)
    "remove" => scenario_remove(global)
    "show" => scenario_show(global)
    "validate" => scenario_validate(global)
    _ =>
      fail(
        TrpgError::Usage(
          "unknown scenario verb: \{verb}",
          Some("supported verbs: list, import, remove, show, validate"),
        ),
      )
  }
}

///|
fn scenario_list(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let scenarios = list_installed_scenarios()
  let json = Json::object({
    "command": "scenario.list",
    "scenarios": Json::array(scenarios.map(scenario_install_row_json)),
  })
  let human = if scenarios.length() == 0 {
    "(シナリオ未導入)"
  } else {
    scenarios.map(format_scenario_install_row).join("\n")
  }
  output_success({ json, human, stderr: "scenario.list" }, global)
}

///|
async fn scenario_import(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let source_ref = need_pos(positions, 2, "scenario url or path")
  let source = load_scenario_source(source_ref)
  let row = install_scenario_source(
    source,
    flag_present(global.args, "--force"),
  )
  let json = Json::object({
    "command": "scenario.import",
    "scenario_id": Json::string(row.id),
    "scenario": scenario_install_row_json(row),
    "installed_path": Json::string(row.path),
    "source_url": match row.source_url {
      Some(value) => Json::string(value)
      None => Json::null()
    },
  })
  json_success(json, "scenario imported: \{row.id}", global)
}

///|
fn scenario_remove(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let scenario_id = need_pos(positions, 2, "scenario id")
  let row = require_installed_scenario(scenario_id)
  ensure_scenario_remove_allowed(scenario_id)
  remove_file_if_exists(row.path)
  remove_file_if_exists(scenario_meta_path(scenario_id))
  let json = Json::object({
    "command": "scenario.remove",
    "scenario": scenario_install_row_json(row),
    "removed": Json::boolean(true),
  })
  json_success(json, "scenario removed: \{scenario_id}", global)
}

///|
async fn scenario_validate(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let scenario_ref = need_pos(positions, 2, "scenario id|path|url")
  let source = load_scenario_source(scenario_ref)
  validate_scenario_json(source.scenario, source.scenario_id)
  let json = Json::object({
    "command": "scenario.validate",
    "scenario_id": Json::string(source.scenario_id),
    "source_kind": Json::string(source.source_kind),
    "source": Json::string(source.source_label),
    "valid": true,
  })
  json_success(json, "scenario valid: \{source.scenario_id}", global)
}

///|
fn scenario_show(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let scenario_id = need_pos(positions, 2, "scenario id")
  let installed = require_installed_scenario(scenario_id)
  let scenario = load_scenario_json(scenario_id)
  validate_scenario_json(scenario, scenario_id)
  let title = json_string_field(scenario, "title", scenario_id)
  let summary = json_string_field(scenario, "summary", "")
  let opening = json_string_field(scenario, "opening_scene", "entrance")
  let interaction_mode = scenario_interaction_mode(scenario)
  let version = json_string_opt_field(scenario, "version")
  let scene_lines = format_scenario_scenes(scenario)
  let npc_lines = format_scenario_npcs(scenario)
  let party_setup = format_party_setup(scenario)
  let goals = format_scenario_goals(scenario)
  let human = "シナリオ: \{title}\n" +
    "id: \{scenario_id}\n" +
    "概要: \{summary}\n" +
    "path: \{installed.path}\n" +
    "origin: \{installed.origin}\n" +
    "interaction_mode: \{format_interaction_mode(interaction_mode)}\n" +
    (match version {
      Some(value) if !value.is_empty() => "version: \{value}\n"
      _ => ""
    }) +
    (match installed.source_url {
      Some(value) if !value.is_empty() => "source_url: \{value}\n"
      _ => ""
    }) +
    "開始シーン: \{opening}\n\n" +
    "## party_setup\n" +
    party_setup +
    "\n\n## scenes\n" +
    scene_lines +
    "\n\n## goals\n" +
    goals +
    "\n\n## npcs\n" +
    npc_lines
  let json = Json::object({
    "command": "scenario.show",
    "scenario_id": Json::string(scenario_id),
    "scenario": scenario,
    "metadata": scenario_install_row_json(installed),
  })
  output_success(
    { json, human, stderr: "scenario.show: \{scenario_id}" },
    global,
  )
}

///|
fn format_scenario_scenes(scenario : Json) -> String {
  match json_get(scenario, "scenes") {
    Some(Object(scenes)) => {
      let lines : Array[String] = []
      for key, value in scenes {
        let description = json_string_field(value, "description", "")
        let difficulty = match scene_difficulty(value) {
          Some(info) => {
            let stat = json_string_field(info, "stat", "")
            let target = json_int_field(info, "target", 0)
            "\{stat} \{target}"
          }
          None => ""
        }
        let transition_count = transition_candidates(value).length()
        let suffix = if difficulty.is_empty() {
          ""
        } else {
          " / 難易度: " + difficulty
        }
        lines.push(
          "- \{key}: \{description}\{suffix} / transitions=\{transition_count}",
        )
      }
      if lines.length() == 0 {
        "(なし)"
      } else {
        lines.join("\n")
      }
    }
    _ => "(なし)"
  }
}

///|
fn format_scenario_npcs(scenario : Json) -> String {
  match json_get(scenario, "npcs") {
    Some(Array(items)) => {
      let lines : Array[String] = []
      for item in items {
        let name = json_string_field(item, "name", "NPC")
        let kind = json_string_field(item, "kind", "npc")
        let sheet = match json_get(item, "sheet") {
          Some(value) => value
          None => Json::object({})
        }
        let stats_text = match json_get(sheet, "stats") {
          Some(Object(stats)) => {
            let stats_json = Json::object(stats)
            let body = json_int_field(stats_json, "body", 0)
            let tech = json_int_field(stats_json, "tech", 0)
            let mind = json_int_field(stats_json, "mind", 0)
            "body=\{body} tech=\{tech} mind=\{mind}"
          }
          _ => "body=0 tech=0 mind=0"
        }
        lines.push("- \{name} [\{kind}] \{stats_text}")
      }
      if lines.length() == 0 {
        "(なし)"
      } else {
        lines.join("\n")
      }
    }
    _ => "(なし)"
  }
}

///|
fn format_scenario_goals(scenario : Json) -> String {
  let lines : Array[String] = []
  for goal in json_array_field(scenario, "goals") {
    let id = json_string_field(goal, "id", "goal")
    let kind = json_string_field(goal, "kind", "")
    let outcome = json_string_field(goal, "outcome", "success")
    let summary = match kind {
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
      _ => kind
    }
    lines.push("- \{id} [\{outcome}] \{summary}")
  }
  if lines.length() == 0 {
    "(なし)"
  } else {
    lines.join("\n")
  }
}

///|
fn format_party_setup(scenario : Json) -> String {
  match json_get(scenario, "party_setup") {
    Some(Object(setup)) => {
      let solo = match setup.get("solo_friendly") {
        Some(True) => "true"
        Some(False) => "false"
        _ => "false"
      }
      let range_text = match setup.get("recommended_party_size") {
        Some(Object(range)) => {
          let min = json_int_field(Json::object(range), "min", 1)
          let max = json_int_field(Json::object(range), "max", min)
          "\{min}-\{max}"
        }
        _ => "(未指定)"
      }
      let sample = match setup.get("sample_pcs") {
        Some(Array(_)) =>
          json_string_array_field(Json::object(setup), "sample_pcs").join(", ")
        _ => ""
      }
      let defaults = match setup.get("default_participants") {
        Some(Object(defaults)) => {
          let lines : Array[String] = []
          for count, names in defaults {
            match names {
              Array(_) => {
                let names_text = match names {
                  Array(values) =>
                    values
                    .map(value => {
                      match value {
                        String(text) => text
                        _ => ""
                      }
                    })
                    .filter(text => !text.is_empty())
                    .join(", ")
                  _ => ""
                }
                lines.push("\{count}: \{names_text}")
              }
              _ => ()
            }
          }
          if lines.length() == 0 {
            "(なし)"
          } else {
            lines.join(" / ")
          }
        }
        _ => "(なし)"
      }
      let sample_text = if sample.is_empty() { "(なし)" } else { sample }
      "- solo_friendly: \{solo}\n- recommended_party_size: \{range_text}\n- sample_pcs: \{sample_text}\n- default_participants: \{defaults}"
    }
    _ => "(なし)"
  }
}

///|
fn dispatch_contest(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let actor_a = need_pos(positions, 1, "actor A")
  let actor_b = need_pos(positions, 2, "actor B")
  let a_stat = normalize_ability(
    match option_value(global.args, "--a-stat") {
      Some(value) => value
      None =>
        fail(
          TrpgError::Usage(
            "missing --a-stat",
            Some("use `trpg contest alice ghost --a-stat tech --b-stat mind`"),
          ),
        )
    },
  )
  let b_stat = normalize_ability(
    match option_value(global.args, "--b-stat") {
      Some(value) => value
      None =>
        fail(
          TrpgError::Usage(
            "missing --b-stat",
            Some("use `trpg contest alice ghost --a-stat tech --b-stat mind`"),
          ),
        )
    },
  )
  let target = match option_value(global.args, "--target") {
    Some(value) => Some(parse_int_arg(value, "target"))
    None => None
  }
  let a_bonus = match option_value(global.args, "--a-bonus") {
    Some(value) => parse_int_arg(value, "a-bonus")
    None => 0
  }
  let b_bonus = match option_value(global.args, "--b-bonus") {
    Some(value) => parse_int_arg(value, "b-bonus")
    None => 0
  }
  let a_tags = parse_tags_csv(option_value(global.args, "--a-tags"))
  let b_tags = parse_tags_csv(option_value(global.args, "--b-tags"))
  let context = option_value(global.args, "--context")
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let row_a = require_character(db, session.id, actor_a)
  let row_b = require_character(db, session.id, actor_b)
  let roll_a = actor_roll(row_a, a_stat, a_bonus, target, a_tags, [], 0, None)
  let roll_b = actor_roll(row_b, b_stat, b_bonus, target, b_tags, [], 0, None)
  if !flag_present(global.args, "--no-consume") {
    if roll_a.consumed_statuses.length() > 0 {
      update_character_conditions(
        db,
        row_a.id,
        consume_statuses_json(row_a.conditions_json, roll_a.consumed_statuses),
      )
    }
    if roll_b.consumed_statuses.length() > 0 {
      update_character_conditions(
        db,
        row_b.id,
        consume_statuses_json(row_b.conditions_json, roll_b.consumed_statuses),
      )
    }
  }
  let roll_a_id = insert_roll_record(
    db,
    session.id,
    roll_a.expr,
    roll_a.total,
    roll_a.rolls,
    roll_a.total_modifier,
    target,
    roll_a.outcome,
    Some(actor_a),
    contest_context_text(context, actor_a, actor_b),
  )
  let roll_b_id = insert_roll_record(
    db,
    session.id,
    roll_b.expr,
    roll_b.total,
    roll_b.rolls,
    roll_b.total_modifier,
    target,
    roll_b.outcome,
    Some(actor_b),
    contest_context_text(context, actor_a, actor_b),
  )
  ignore(
    append_event(
      db,
      session.id,
      "roll",
      Some(actor_a),
      Some(a_stat),
      roll_event_text(
        actor_a,
        roll_a.expr,
        roll_a.total,
        target,
        roll_a.outcome,
        roll_a.margin,
        roll_a.special,
        [],
        contest_context_text(context, actor_a, actor_b),
      ),
      actor_roll_json(roll_a).stringify(),
    ),
  )
  ignore(
    append_event(
      db,
      session.id,
      "roll",
      Some(actor_b),
      Some(b_stat),
      roll_event_text(
        actor_b,
        roll_b.expr,
        roll_b.total,
        target,
        roll_b.outcome,
        roll_b.margin,
        roll_b.special,
        [],
        contest_context_text(context, actor_a, actor_b),
      ),
      actor_roll_json(roll_b).stringify(),
    ),
  )
  let winner = if roll_a.total > roll_b.total {
    Some(actor_a)
  } else if roll_b.total > roll_a.total {
    Some(actor_b)
  } else {
    None
  }
  let margin = if roll_a.total >= roll_b.total {
    roll_a.total - roll_b.total
  } else {
    roll_b.total - roll_a.total
  }
  let contest_text = match winner {
    Some(name) =>
      "対抗判定 \{actor_a}(\{roll_a.total}) vs \{actor_b}(\{roll_b.total}) -> \{name} / margin=\{margin}"
    None =>
      "対抗判定 \{actor_a}(\{roll_a.total}) vs \{actor_b}(\{roll_b.total}) -> tie"
  }
  let event_id = append_event(
    db,
    session.id,
    "contest",
    None,
    None,
    contest_text,
    Json::object({
      "actor_a": actor_roll_json(roll_a),
      "actor_b": actor_roll_json(roll_b),
      "winner": match winner {
        Some(value) => Json::string(value)
        None => Json::null()
      },
      "margin": j_int(margin),
      "roll_a_id": j_int(roll_a_id),
      "roll_b_id": j_int(roll_b_id),
    }).stringify(),
  )
  let json = Json::object({
    "command": "contest",
    "actor_a": actor_roll_json(roll_a),
    "actor_b": actor_roll_json(roll_b),
    "winner": match winner {
      Some(value) => Json::string(value)
      None => Json::null()
    },
    "margin": j_int(margin),
    "event_id": j_int(event_id),
  })
  output_success({ json, human: contest_text, stderr: contest_text }, global)
}

///|
fn dispatch_attack(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let attacker = need_pos(positions, 1, "attacker")
  let defender = need_pos(positions, 2, "defender")
  let atk_stat = normalize_ability(
    match option_value(global.args, "--atk") {
      Some(value) => value
      None =>
        fail(
          TrpgError::Usage(
            "missing --atk",
            Some(
              "use `trpg attack ghost alice --atk mind --def tech --damage 1d6`",
            ),
          ),
        )
    },
  )
  let def_stat = normalize_ability(
    match option_value(global.args, "--def") {
      Some(value) => value
      None =>
        fail(
          TrpgError::Usage(
            "missing --def",
            Some(
              "use `trpg attack ghost alice --atk mind --def tech --damage 1d6`",
            ),
          ),
        )
    },
  )
  let damage_expr = match option_value(global.args, "--damage") {
    Some(value) => value
    None =>
      fail(
        TrpgError::Usage(
          "missing --damage",
          Some(
            "use `trpg attack ghost alice --atk mind --def tech --damage 1d6`",
          ),
        ),
      )
  }
  let atk_bonus = match option_value(global.args, "--atk-bonus") {
    Some(value) => parse_int_arg(value, "atk-bonus")
    None => 0
  }
  let def_bonus = match option_value(global.args, "--def-bonus") {
    Some(value) => parse_int_arg(value, "def-bonus")
    None => 0
  }
  let atk_tags = parse_tags_csv(option_value(global.args, "--atk-tags"))
  let def_tags = parse_tags_csv(option_value(global.args, "--def-tags"))
  let context = option_value(global.args, "--context")
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let row_atk = require_character(db, session.id, attacker)
  let row_def = require_character(db, session.id, defender)
  let roll_atk = actor_roll(
    row_atk,
    atk_stat,
    atk_bonus,
    None,
    atk_tags,
    [],
    0,
    None,
  )
  let roll_def = actor_roll(
    row_def,
    def_stat,
    def_bonus,
    None,
    def_tags,
    [],
    0,
    None,
  )
  if !flag_present(global.args, "--no-consume") {
    if roll_atk.consumed_statuses.length() > 0 {
      update_character_conditions(
        db,
        row_atk.id,
        consume_statuses_json(
          row_atk.conditions_json,
          roll_atk.consumed_statuses,
        ),
      )
    }
    if roll_def.consumed_statuses.length() > 0 {
      update_character_conditions(
        db,
        row_def.id,
        consume_statuses_json(
          row_def.conditions_json,
          roll_def.consumed_statuses,
        ),
      )
    }
  }
  let contest_text = contest_context_text(context, attacker, defender)
  ignore(
    insert_roll_record(
      db,
      session.id,
      roll_atk.expr,
      roll_atk.total,
      roll_atk.rolls,
      roll_atk.total_modifier,
      None,
      roll_atk.outcome,
      Some(attacker),
      contest_text,
    ),
  )
  ignore(
    append_event(
      db,
      session.id,
      "roll",
      Some(attacker),
      Some(atk_stat),
      roll_event_text(
        attacker,
        roll_atk.expr,
        roll_atk.total,
        None,
        roll_atk.outcome,
        roll_atk.margin,
        roll_atk.special,
        [],
        contest_text,
      ),
      actor_roll_json(roll_atk).stringify(),
    ),
  )
  ignore(
    insert_roll_record(
      db,
      session.id,
      roll_def.expr,
      roll_def.total,
      roll_def.rolls,
      roll_def.total_modifier,
      None,
      roll_def.outcome,
      Some(defender),
      contest_text,
    ),
  )
  ignore(
    append_event(
      db,
      session.id,
      "roll",
      Some(defender),
      Some(def_stat),
      roll_event_text(
        defender,
        roll_def.expr,
        roll_def.total,
        None,
        roll_def.outcome,
        roll_def.margin,
        roll_def.special,
        [],
        contest_text,
      ),
      actor_roll_json(roll_def).stringify(),
    ),
  )
  let winner = if roll_atk.total > roll_def.total {
    Some(attacker)
  } else if roll_def.total > roll_atk.total {
    Some(defender)
  } else {
    None
  }
  let margin = if roll_atk.total >= roll_def.total {
    roll_atk.total - roll_def.total
  } else {
    roll_def.total - roll_atk.total
  }
  ignore(
    append_event(
      db,
      session.id,
      "contest",
      None,
      None,
      match winner {
        Some(name) =>
          "対抗判定 \{attacker}(\{roll_atk.total}) vs \{defender}(\{roll_def.total}) -> \{name} / margin=\{margin}"
        None =>
          "対抗判定 \{attacker}(\{roll_atk.total}) vs \{defender}(\{roll_def.total}) -> tie"
      },
      Json::object({
        "actor_a": actor_roll_json(roll_atk),
        "actor_b": actor_roll_json(roll_def),
        "winner": match winner {
          Some(value) => Json::string(value)
          None => Json::null()
        },
        "margin": j_int(margin),
      }).stringify(),
    ),
  )
  let defender_next = if winner == Some(attacker) {
    let damage = eval_dice(damage_expr)
    let next_hp = clamp_int(row_def.hp_cur - damage.total, 0, row_def.hp_max)
    execute_bound(db, "UPDATE statuses SET hp_cur = ? WHERE character_id = ?", [
      int_value(next_hp),
      int_value(row_def.id),
    ])
    ignore(
      append_event(
        db,
        session.id,
        "hp",
        Some(attacker),
        Some(defender),
        "\{attacker} deals \{damage.total} to \{defender}",
        Json::object({
          "damage_expr": Json::string(damage_expr),
          "damage_total": j_int(damage.total),
          "hp_cur": j_int(next_hp),
          "hp_max": j_int(row_def.hp_max),
        }).stringify(),
      ),
    )
    next_hp
  } else {
    row_def.hp_cur
  }
  let attack_text = match winner {
    Some(name) if name == attacker =>
      "\{attacker} attacks \{defender} -> hit / defender HP \{row_def.hp_cur} -> \{defender_next}"
    Some(_) => "\{attacker} attacks \{defender} -> blocked"
    None => "\{attacker} attacks \{defender} -> tie"
  }
  let event_id = append_event(
    db,
    session.id,
    "attack",
    Some(attacker),
    Some(defender),
    attack_text,
    Json::object({
      "attacker": actor_roll_json(roll_atk),
      "defender": actor_roll_json(roll_def),
      "winner": match winner {
        Some(value) => Json::string(value)
        None => Json::null()
      },
      "margin": j_int(margin),
      "damage_expr": Json::string(damage_expr),
      "defender_hp": j_int(defender_next),
    }).stringify(),
  )
  let json = Json::object({
    "command": "attack",
    "attacker": actor_roll_json(roll_atk),
    "defender": actor_roll_json(roll_def),
    "winner": match winner {
      Some(value) => Json::string(value)
      None => Json::null()
    },
    "margin": j_int(margin),
    "damage_expr": Json::string(damage_expr),
    "defender_hp": j_int(defender_next),
    "event_id": j_int(event_id),
  })
  output_success({ json, human: attack_text, stderr: attack_text }, global)
}

///|
fn contest_context_text(
  context : String?,
  actor_a : String,
  actor_b : String,
) -> String? {
  match context {
    Some(value) if !value.is_empty() =>
      Some("\{value} / contest \{actor_a} vs \{actor_b}")
    _ => Some("contest \{actor_a} vs \{actor_b}")
  }
}
