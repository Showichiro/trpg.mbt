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
    "end" => session_end(global)
    "scene" => session_scene(global)
    "note" => session_note(global)
    _ =>
      fail(
        TrpgError::Usage(
          "unknown session verb: \{verb}",
          Some("supported verbs: init, show, end, scene, note"),
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
      let opening = json_string_field(scenario, "opening_scene", "entrance")
      execute_bound(
        db,
        "INSERT INTO sessions (scenario_id, started_at_ms, current_scene, is_active) VALUES (?, ?, ?, 1)",
        [text_value(scenario_id), int64_value(now_ms()), text_value(opening)],
      )
      let session_id = db.last_insert_rowid().to_int()
      insert_scenario_scenes(db, session_id, scenario)
      insert_scenario_npcs(db, session_id, scenario)
      let session = SessionRow::{
        id: session_id,
        scenario_id,
        started_at_ms: now_ms(),
        current_scene: opening,
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
  let pcs = list_characters(db, session.id).map(row_to_character_json)
  let json = Json::object({
    "command": "session.show",
    "session": session_json(session),
    "characters": Json::array(pcs),
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
  execute_bound(db, "UPDATE sessions SET is_active = 0 WHERE id = ?", [
    int_value(session.id),
  ])
  let json = Json::object({
    "command": "session.end",
    "session_id": j_int(session.id),
    "scenario_id": Json::string(session.scenario_id),
    "active": false,
  })
  json_success(json, "セッション終了: \{session.scenario_id}", global)
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
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let id = append_log(db, session.id, "gm", text)
  let json = Json::object({
    "command": "session.note",
    "log_id": j_int(id),
    "session_id": j_int(session.id),
    "text": Json::string(text),
  })
  json_success(json, "note[\{id}] \{text}", global)
}

///|
fn session_json(session : SessionRow) -> Json {
  Json::object({
    "id": j_int(session.id),
    "scenario_id": Json::string(session.scenario_id),
    "started_at_ms": j_i64(session.started_at_ms),
    "current_scene": Json::string(session.current_scene),
    "active": true,
  })
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
  let log_id = match note {
    Some(text) if !text.is_empty() =>
      Some(
        append_log(db, session.id, "gm", "シーン遷移 -> \{key}: \{text}"),
      )
    _ => None
  }
  let json : Map[String, Json] = {
    "command": Json::string("session.scene"),
    "session_id": j_int(session.id),
    "current_scene": Json::string(key),
  }
  match note {
    Some(text) if !text.is_empty() => json["note"] = Json::string(text)
    _ => ()
  }
  match log_id {
    Some(value) => json["log_id"] = j_int(value)
    None => ()
  }
  let human = match note {
    Some(text) if !text.is_empty() => "scene -> \{key} / \{text}"
    _ => "scene -> \{key}"
  }
  json_success(Json::object(json), human, global)
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
    _ =>
      fail(
        TrpgError::Usage(
          "unknown pc verb: \{verb}",
          Some("supported verbs: add, show"),
        ),
      )
  }
}

///|
fn pc_add(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let name = need_pos(positions, 2, "pc name")
  let from_path = match option_value(global.args, "--from") {
    Some(path) => path
    None =>
      fail(
        TrpgError::Usage(
          "missing --from",
          Some("use `trpg pc add alice --from path.json`"),
        ),
      )
  }
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
  let hp_max = json_int_field(sheet, "hp_max", 8)
  let id = insert_character(
    db,
    session.id,
    name,
    "pc",
    sheet.stringify(),
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
      let preview = roll_preview(row, ability)
      let json = Json::object({
        "command": "pc.show",
        "character": row_to_character_json(row),
        "roll_preview": roll_preview_json(preview),
      })
      json_success(json, format_roll_preview(row.name, preview), global)
    }
    None => {
      let json = Json::object({
        "command": "pc.show",
        "character": row_to_character_json(row),
      })
      json_success(json, "\{row.name}: HP \{row.hp_cur}/\{row.hp_max}", global)
    }
  }
}

///|
fn dispatch_roll(global : GlobalArgs) -> RunResult raise TrpgFailure {
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
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let rolls_json = json_int_array(roll.rolls).stringify()
  execute_bound(
    db,
    "INSERT INTO rolls (session_id, expr, total, rolls_json, mod, target, outcome, rolled_by, context, created_at_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    [
      int_value(session.id),
      text_value(expr),
      int_value(roll.total),
      text_value(rolls_json),
      int_value(roll.mod),
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
  let roll_id = db.last_insert_rowid().to_int()
  let json = Json::object({
    "command": "roll",
    "expr": Json::string(expr),
    "total": j_int(roll.total),
    "rolls": json_int_array(roll.rolls),
    "mod": j_int(roll.mod),
    "target": match target {
      Some(v) => j_int(v)
      None => Json::null()
    },
    "outcome": Json::string(outcome),
    "roll_id": j_int(roll_id),
  })
  let target_text = match target {
    Some(v) => " (target \{v} -> \{outcome})"
    None => ""
  }
  json_success(
    json,
    "\{expr} = \{roll.breakdown} = \{roll.total}\{target_text}",
    global,
  )
}

///|
fn dispatch_hp(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let name = need_pos(positions, 1, "character name")
  let delta = parse_int_arg(need_pos(positions, 2, "hp delta"), "hp delta")
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
  let tag = need_pos(positions, 3, "status tag")
  let note = option_value(global.args, "--note").unwrap_or("")
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let row = require_character(db, session.id, name)
  let conditions_json = match op {
    "add" =>
      add_condition(
        row.conditions_json,
        tag,
        note,
        option_value(global.args, "--modifier"),
        match option_value(global.args, "--uses") {
          Some(value) => Some(parse_int_arg(value, "uses"))
          None => None
        },
        option_value(global.args, "--duration"),
        option_value(global.args, "--on-trigger"),
      )
    "remove" => remove_condition(row.conditions_json, tag)
    _ =>
      fail(
        TrpgError::Usage(
          "unknown status operation: \{op}",
          Some("supported operations: add, remove"),
        ),
      )
  }
  update_character_conditions(db, row.id, conditions_json)
  let json = Json::object({
    "command": "status",
    "name": Json::string(name),
    "operation": Json::string(op),
    "tag": Json::string(tag),
    "conditions": parse_json(conditions_json, "conditions_json"),
  })
  json_success(json, "\{name}: status \{op} \{tag}", global)
}

///|
fn add_condition(
  source : String,
  tag : String,
  note : String,
  modifier : String?,
  uses : Int?,
  duration : String?,
  on_trigger : String?,
) -> String raise TrpgFailure {
  let arr = match parse_json(source, "conditions_json") {
    Array(items) => items
    _ => []
  }
  let condition : Map[String, Json] = {
    "name": Json::string(tag),
    "note": Json::string(note),
    "applied_at_ms": j_i64(now_ms()),
  }
  match modifier {
    Some(value) =>
      condition["modifier"] = Json::string(normalize_modifier_spec(value))
    None => ()
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
    _ =>
      fail(
        TrpgError::Usage(
          "unknown log verb: \{verb}",
          Some("supported verbs: add, tail"),
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
  let json = Json::object({
    "command": "log.add",
    "log_id": j_int(id),
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
fn dispatch_item(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let verb = need_pos(positions, 1, "item verb")
  match verb {
    "give" => item_give(global)
    "drop" => item_drop(global)
    "list" => item_list(global)
    _ =>
      fail(
        TrpgError::Usage(
          "unknown item verb: \{verb}",
          Some("supported verbs: give, drop, list"),
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
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let row = require_character(db, session.id, name)
  let next_sheet = add_inventory_item_json(row.sheet_json, item)
  update_character_sheet(db, row.id, next_sheet)
  let text = match note {
    Some(value) if !value.is_empty() =>
      "\{name} が \{item} を獲得: \{value}"
    _ => "\{name} が \{item} を獲得"
  }
  let log_id = append_log(db, session.id, "gm", text)
  let updated = require_character(db, session.id, name)
  let json = Json::object({
    "command": "item.give",
    "name": Json::string(name),
    "item": Json::string(item),
    "log_id": j_int(log_id),
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
  let log_id = append_log(db, session.id, "gm", text)
  let updated = require_character(db, session.id, name)
  let json = Json::object({
    "command": "item.drop",
    "name": Json::string(name),
    "item": Json::string(item),
    "log_id": j_int(log_id),
    "inventory": Json::array(
      inventory_from_sheet_json(updated.sheet_json).map(value => {
        Json::string(value)
      }),
    ),
  })
  json_success(json, "\{name}: \{item} を失う", global)
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
    "flag" => scene_flag(global)
    _ =>
      fail(
        TrpgError::Usage(
          "unknown scene verb: \{verb}",
          Some("supported verbs: set, flag"),
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
  json_success(json, "flag[\{session.current_scene}] \{key}=\{value}", global)
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
fn dispatch_scenario(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let verb = need_pos(positions, 1, "scenario verb")
  match verb {
    "show" => scenario_show(global)
    _ =>
      fail(
        TrpgError::Usage(
          "unknown scenario verb: \{verb}",
          Some("supported verbs: show"),
        ),
      )
  }
}

///|
fn scenario_show(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let scenario_id = need_pos(positions, 2, "scenario id")
  let scenario = load_scenario_json(scenario_id)
  let title = json_string_field(scenario, "title", scenario_id)
  let summary = json_string_field(scenario, "summary", "")
  let opening = json_string_field(scenario, "opening_scene", "entrance")
  let scene_lines = format_scenario_scenes(scenario)
  let npc_lines = format_scenario_npcs(scenario)
  let party_setup = format_party_setup(scenario)
  let human = "シナリオ: \{title}\n" +
    "id: \{scenario_id}\n" +
    "概要: \{summary}\n" +
    "開始シーン: \{opening}\n\n" +
    "## party_setup\n" +
    party_setup +
    "\n\n## scenes\n" +
    scene_lines +
    "\n\n## npcs\n" +
    npc_lines
  let json = Json::object({
    "command": "scenario.show",
    "scenario_id": Json::string(scenario_id),
    "scenario": scenario,
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
        let hint = json_string_field(value, "difficulty_hint", "")
        let suffix = if hint.is_empty() {
          ""
        } else {
          " / 難易度目安: " + hint
        }
        lines.push("- \{key}: \{description}\{suffix}")
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
