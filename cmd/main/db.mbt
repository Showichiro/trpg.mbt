///|
fn text_value(value : String) -> @sqlite.SqlValue {
  @sqlite.SqlValue::Text(@utf8.encode(value))
}

///|
fn int_value(value : Int) -> @sqlite.SqlValue {
  @sqlite.SqlValue::Int(value)
}

///|
fn int64_value(value : Int64) -> @sqlite.SqlValue {
  @sqlite.SqlValue::Int64(value)
}

///|
fn trpg_home() -> String raise TrpgFailure {
  match @env.get_env_var("TRPG_HOME") {
    Some(value) if !value.is_empty() => strip_trailing_slash(value)
    _ =>
      match @env.get_env_var("HOME") {
        Some(home) if !home.is_empty() => home + "/.trpg"
        _ =>
          fail(
            TrpgError::Permission(
              "HOME is not set",
              Some("set TRPG_HOME or HOME"),
            ),
          )
      }
  }
}

///|
fn strip_trailing_slash(path : String) -> String {
  if path.length() > 1 && path.has_suffix("/") {
    path[:path.length() - 1].to_string()
  } else {
    path
  }
}

///|
fn scenarios_dir() -> String raise TrpgFailure {
  trpg_home() + "/scenarios"
}

///|
fn scenario_path(id : String) -> String raise TrpgFailure {
  scenarios_dir() + "/" + id + ".json"
}

///|
fn ensure_dir(path : String) -> Unit raise TrpgFailure {
  if @fs.path_exists(path) {
    ()
  } else {
    @fs.create_dir(path) catch {
      err =>
        fail(
          TrpgError::Permission(
            "failed to create directory: \{path}",
            Some(err.to_string()),
          ),
        )
    }
  }
}

///|
fn ensure_home_dirs() -> Unit raise TrpgFailure {
  let home = trpg_home()
  ensure_dir(home)
  ensure_dir(home + "/scenarios")
}

///|
fn open_db() -> @sqlite.Database raise TrpgFailure {
  ensure_home_dirs()
  let home = trpg_home()
  match @sqlite.Database::open(home + "/trpg.db") {
    Some(db) => {
      migrate(db)
      db
    }
    None =>
      fail(
        TrpgError::Permission(
          "failed to open sqlite database",
          Some("check write permission for \{home}"),
        ),
      )
  }
}

///|
fn db_error(db : @sqlite.Database) -> String {
  "sqlite error code=\{db.errcode()} extended=\{db.extended_errcode()}"
}

///|
fn column_int64(stmt : @sqlite.Statement, col : Int) -> Int64 {
  match stmt.column(col) {
    Int64(value) => value
    Int(value) => value.to_int64()
    _ => 0L
  }
}

///|
fn column_string(stmt : @sqlite.Statement, col : Int) -> String {
  match stmt.column(col) {
    Text(value) => bytes_to_string(value)
    _ => ""
  }
}

///|
fn column_opt_string(stmt : @sqlite.Statement, col : Int) -> String? {
  match stmt.column(col) {
    Text(value) => Some(bytes_to_string(value))
    _ => None
  }
}

///|
fn column_opt_int(stmt : @sqlite.Statement, col : Int) -> Int? {
  match stmt.column(col) {
    Int(value) => Some(value)
    Int64(value) => Some(value.to_int())
    _ => None
  }
}

///|
fn exec_sql(db : @sqlite.Database, sql : String) -> Unit raise TrpgFailure {
  if db.exec(sql) {
    ()
  } else {
    fail(TrpgError::General("sqlite exec failed", Some(db_error(db))))
  }
}

///|
fn table_has_column(
  db : @sqlite.Database,
  table_name : String,
  column_name : String,
) -> Bool raise TrpgFailure {
  let stmt = prepare(db, "PRAGMA table_info(\{table_name})")
  let mut found = false
  while stmt.step() {
    if column_string(stmt, 1) == column_name {
      found = true
    }
  }
  finish_statement(stmt)
  found
}

///|
fn prepare(
  db : @sqlite.Database,
  sql : String,
) -> @sqlite.Statement raise TrpgFailure {
  match db.prepare(sql) {
    Some(stmt) => stmt
    None =>
      fail(TrpgError::General("sqlite prepare failed", Some(db_error(db))))
  }
}

///|
fn execute_bound(
  db : @sqlite.Database,
  sql : String,
  values : Array[@sqlite.SqlValue],
) -> Unit raise TrpgFailure {
  let stmt = prepare(db, sql)
  let bound = stmt.bind_all(values)
  let ok = if bound { stmt.execute() } else { false }
  finish_statement(stmt)
  if ok {
    ()
  } else {
    fail(TrpgError::General("sqlite statement failed", Some(db_error(db))))
  }
}

///|
fn finish_statement(_stmt : @sqlite.Statement) -> Unit {
  // mizchi/sqlite 0.2.4 can crash intermittently in sqlite3_finalize on macOS arm64.
  // This CLI is short-lived per invocation, so letting the process reclaim statements
  // is safer than finalizing through the current binding.
  ()
}

///|
fn migrate(db : @sqlite.Database) -> Unit raise TrpgFailure {
  let create_sessions =
    #|CREATE TABLE IF NOT EXISTS sessions (
    #|  id INTEGER PRIMARY KEY AUTOINCREMENT,
    #|  scenario_id TEXT NOT NULL,
    #|  started_at_ms INTEGER NOT NULL,
    #|  current_scene TEXT NOT NULL,
    #|  is_active INTEGER NOT NULL DEFAULT 1,
    #|  ended_at_ms INTEGER,
    #|  outcome TEXT
    #|);
  exec_sql(db, create_sessions)
  if !table_has_column(db, "sessions", "ended_at_ms") {
    exec_sql(db, "ALTER TABLE sessions ADD COLUMN ended_at_ms INTEGER")
  }
  if !table_has_column(db, "sessions", "outcome") {
    exec_sql(db, "ALTER TABLE sessions ADD COLUMN outcome TEXT")
  }
  let create_active_index =
    #|CREATE UNIQUE INDEX IF NOT EXISTS idx_sessions_one_active
    #|ON sessions(is_active) WHERE is_active = 1;
  exec_sql(db, create_active_index)
  let create_characters =
    #|CREATE TABLE IF NOT EXISTS characters (
    #|  id INTEGER PRIMARY KEY AUTOINCREMENT,
    #|  session_id INTEGER NOT NULL,
    #|  name TEXT NOT NULL,
    #|  kind TEXT NOT NULL,
    #|  sheet_json TEXT NOT NULL,
    #|  UNIQUE(session_id, name)
    #|);
  exec_sql(db, create_characters)
  let create_statuses =
    #|CREATE TABLE IF NOT EXISTS statuses (
    #|  character_id INTEGER PRIMARY KEY,
    #|  hp_cur INTEGER NOT NULL,
    #|  hp_max INTEGER NOT NULL,
    #|  conditions_json TEXT NOT NULL
    #|);
  exec_sql(db, create_statuses)
  let create_rolls =
    #|CREATE TABLE IF NOT EXISTS rolls (
    #|  id INTEGER PRIMARY KEY AUTOINCREMENT,
    #|  session_id INTEGER NOT NULL,
    #|  expr TEXT NOT NULL,
    #|  total INTEGER NOT NULL,
    #|  rolls_json TEXT NOT NULL,
    #|  mod INTEGER NOT NULL,
    #|  target INTEGER,
    #|  outcome TEXT NOT NULL,
    #|  rolled_by TEXT,
    #|  context TEXT,
    #|  created_at_ms INTEGER NOT NULL
    #|);
  exec_sql(db, create_rolls)
  let create_logs =
    #|CREATE TABLE IF NOT EXISTS logs (
    #|  id INTEGER PRIMARY KEY AUTOINCREMENT,
    #|  session_id INTEGER NOT NULL,
    #|  actor TEXT NOT NULL,
    #|  visibility TEXT NOT NULL DEFAULT 'all',
    #|  text TEXT NOT NULL,
    #|  created_at_ms INTEGER NOT NULL
    #|);
  exec_sql(db, create_logs)
  let create_scenes =
    #|CREATE TABLE IF NOT EXISTS scenes (
    #|  session_id INTEGER NOT NULL,
    #|  key TEXT NOT NULL,
    #|  state_json TEXT NOT NULL,
    #|  flags_json TEXT NOT NULL,
    #|  PRIMARY KEY(session_id, key)
    #|);
  exec_sql(db, create_scenes)
  let create_events =
    #|CREATE TABLE IF NOT EXISTS events (
    #|  id INTEGER PRIMARY KEY AUTOINCREMENT,
    #|  session_id INTEGER NOT NULL,
    #|  kind TEXT NOT NULL,
    #|  actor TEXT,
    #|  subject TEXT,
    #|  text TEXT NOT NULL,
    #|  data_json TEXT NOT NULL,
    #|  created_at_ms INTEGER NOT NULL
    #|);
  exec_sql(db, create_events)
  exec_sql(
    db, "CREATE INDEX IF NOT EXISTS idx_events_session_created ON events(session_id, created_at_ms, id)",
  )
  exec_sql(
    db, "CREATE INDEX IF NOT EXISTS idx_events_session_kind_created ON events(session_id, kind, created_at_ms, id)",
  )
  exec_sql(db, "PRAGMA user_version = 2")
}

///|
fn active_session(db : @sqlite.Database) -> SessionRow? raise TrpgFailure {
  let stmt = prepare(
    db, "SELECT id, scenario_id, started_at_ms, current_scene, is_active, ended_at_ms, outcome FROM sessions WHERE is_active = 1 LIMIT 1",
  )
  let result = if stmt.step() {
    Some({
      id: stmt.column_int(0),
      scenario_id: column_string(stmt, 1),
      started_at_ms: column_int64(stmt, 2),
      current_scene: column_string(stmt, 3),
      is_active: stmt.column_int(4) == 1,
      ended_at_ms: match stmt.column(5) {
        Int64(value) => Some(value)
        Int(value) => Some(value.to_int64())
        _ => None
      },
      outcome: column_opt_string(stmt, 6),
    })
  } else {
    None
  }
  finish_statement(stmt)
  result
}

///|
fn latest_session(db : @sqlite.Database) -> SessionRow? raise TrpgFailure {
  let stmt = prepare(
    db, "SELECT id, scenario_id, started_at_ms, current_scene, is_active, ended_at_ms, outcome FROM sessions ORDER BY id DESC LIMIT 1",
  )
  let result = if stmt.step() {
    Some({
      id: stmt.column_int(0),
      scenario_id: column_string(stmt, 1),
      started_at_ms: column_int64(stmt, 2),
      current_scene: column_string(stmt, 3),
      is_active: stmt.column_int(4) == 1,
      ended_at_ms: match stmt.column(5) {
        Int64(value) => Some(value)
        Int(value) => Some(value.to_int64())
        _ => None
      },
      outcome: column_opt_string(stmt, 6),
    })
  } else {
    None
  }
  finish_statement(stmt)
  result
}

///|
fn require_active_session(
  db : @sqlite.Database,
) -> SessionRow raise TrpgFailure {
  match active_session(db) {
    Some(session) => session
    None =>
      fail(
        TrpgError::NotFound(
          "active session is not set",
          Some("run `trpg session init forgotten_library` first"),
        ),
      )
  }
}

///|
fn read_text_file(path : String) -> String raise TrpgFailure {
  @fs.read_file_to_string(path) catch {
    err =>
      fail(
        TrpgError::NotFound(
          "failed to read file: \{path}",
          Some(err.to_string()),
        ),
      )
  }
}

///|
fn load_scenario_json(id : String) -> Json raise TrpgFailure {
  let path = scenario_path(id)
  let source = read_text_file(path)
  parse_json(source, path)
}

///|
fn insert_character(
  db : @sqlite.Database,
  session_id : Int,
  name : String,
  kind : String,
  sheet_json : String,
  hp_max : Int,
) -> Int raise TrpgFailure {
  execute_bound(
    db,
    "INSERT INTO characters (session_id, name, kind, sheet_json) VALUES (?, ?, ?, ?)",
    [
      int_value(session_id),
      text_value(name),
      text_value(kind),
      text_value(sheet_json),
    ],
  )
  let id = db.last_insert_rowid().to_int()
  execute_bound(
    db,
    "INSERT INTO statuses (character_id, hp_cur, hp_max, conditions_json) VALUES (?, ?, ?, ?)",
    [int_value(id), int_value(hp_max), int_value(hp_max), text_value("[]")],
  )
  id
}

///|
fn update_character_sheet(
  db : @sqlite.Database,
  character_id : Int,
  sheet_json : String,
) -> Unit raise TrpgFailure {
  execute_bound(db, "UPDATE characters SET sheet_json = ? WHERE id = ?", [
    text_value(sheet_json),
    int_value(character_id),
  ])
}

///|
fn update_character_conditions(
  db : @sqlite.Database,
  character_id : Int,
  conditions_json : String,
) -> Unit raise TrpgFailure {
  execute_bound(
    db,
    "UPDATE statuses SET conditions_json = ? WHERE character_id = ?",
    [text_value(conditions_json), int_value(character_id)],
  )
}

///|
fn append_log(
  db : @sqlite.Database,
  session_id : Int,
  actor : String,
  text : String,
) -> Int raise TrpgFailure {
  execute_bound(
    db,
    "INSERT INTO logs (session_id, actor, text, created_at_ms) VALUES (?, ?, ?, ?)",
    [
      int_value(session_id),
      text_value(actor),
      text_value(text),
      int64_value(now_ms()),
    ],
  )
  db.last_insert_rowid().to_int()
}

///|
fn append_event(
  db : @sqlite.Database,
  session_id : Int,
  kind : String,
  actor : String?,
  subject : String?,
  text : String,
  data_json : String,
) -> Int raise TrpgFailure {
  execute_bound(
    db,
    "INSERT INTO events (session_id, kind, actor, subject, text, data_json, created_at_ms) VALUES (?, ?, ?, ?, ?, ?, ?)",
    [
      int_value(session_id),
      text_value(kind),
      match actor {
        Some(value) => text_value(value)
        None => @sqlite.SqlValue::Null
      },
      match subject {
        Some(value) => text_value(value)
        None => @sqlite.SqlValue::Null
      },
      text_value(text),
      text_value(data_json),
      int64_value(now_ms()),
    ],
  )
  db.last_insert_rowid().to_int()
}

///|
fn find_character(
  db : @sqlite.Database,
  session_id : Int,
  name : String,
) -> CharacterRow? raise TrpgFailure {
  let sql =
    #|SELECT c.id, c.name, c.kind, c.sheet_json, s.hp_cur, s.hp_max, s.conditions_json
    #|FROM characters c JOIN statuses s ON s.character_id = c.id
    #|WHERE c.session_id = ? AND c.name = ?
    #|LIMIT 1
  let stmt = prepare(db, sql)
  stmt.bind_all([int_value(session_id), text_value(name)]) |> ignore
  let result = if stmt.step() {
    Some({
      id: stmt.column_int(0),
      name: column_string(stmt, 1),
      kind: column_string(stmt, 2),
      sheet_json: column_string(stmt, 3),
      hp_cur: stmt.column_int(4),
      hp_max: stmt.column_int(5),
      conditions_json: column_string(stmt, 6),
    })
  } else {
    None
  }
  finish_statement(stmt)
  result
}

///|
fn require_character(
  db : @sqlite.Database,
  session_id : Int,
  name : String,
) -> CharacterRow raise TrpgFailure {
  match find_character(db, session_id, name) {
    Some(row) => row
    None =>
      fail(
        TrpgError::NotFound(
          "character not found: \{name}",
          Some("run `trpg pc add \{name} --from <path>` first"),
        ),
      )
  }
}

///|
fn row_to_character_json(row : CharacterRow) -> Json {
  let sheet = parse_json(row.sheet_json, "sheet_json") catch {
    _ => Json::object({})
  }
  let conditions = parse_json(row.conditions_json, "conditions_json") catch {
    _ => Json::array([])
  }
  let object : Map[String, Json] = {
    "id": j_int(row.id),
    "name": Json::string(row.name),
    "kind": Json::string(row.kind),
    "hp_cur": j_int(row.hp_cur),
    "hp_max": j_int(row.hp_max),
    "conditions": conditions,
    "sheet": sheet,
  }
  let play_style = play_style_from_sheet_json(row.sheet_json) catch {
    _ => None
  }
  match play_style {
    Some(style) => object["play_style"] = play_style_json(style)
    None => object["play_style"] = Json::null()
  }
  Json::object(object)
}

///|
fn list_characters(
  db : @sqlite.Database,
  session_id : Int,
) -> Array[CharacterRow] raise TrpgFailure {
  let sql =
    #|SELECT c.id, c.name, c.kind, c.sheet_json, s.hp_cur, s.hp_max, s.conditions_json
    #|FROM characters c JOIN statuses s ON s.character_id = c.id
    #|WHERE c.session_id = ?
    #|ORDER BY c.id
  let stmt = prepare(db, sql)
  stmt.bind_all([int_value(session_id)]) |> ignore
  let rows : Array[CharacterRow] = []
  while stmt.step() {
    rows.push({
      id: stmt.column_int(0),
      name: column_string(stmt, 1),
      kind: column_string(stmt, 2),
      sheet_json: column_string(stmt, 3),
      hp_cur: stmt.column_int(4),
      hp_max: stmt.column_int(5),
      conditions_json: column_string(stmt, 6),
    })
  }
  finish_statement(stmt)
  rows
}

///|
fn recent_logs(
  db : @sqlite.Database,
  session_id : Int,
  limit : Int,
) -> Array[LogRow] raise TrpgFailure {
  let stmt = prepare(
    db, "SELECT id, actor, text, created_at_ms FROM logs WHERE session_id = ? ORDER BY id DESC LIMIT ?",
  )
  stmt.bind_all([int_value(session_id), int_value(limit)]) |> ignore
  let rows : Array[LogRow] = []
  while stmt.step() {
    rows.push({
      id: stmt.column_int(0),
      actor: column_string(stmt, 1),
      text: column_string(stmt, 2),
      created_at_ms: column_int64(stmt, 3),
    })
  }
  finish_statement(stmt)
  rows.rev()
}

///|
fn recent_rolls(
  db : @sqlite.Database,
  session_id : Int,
  limit : Int,
) -> Array[RollRow] raise TrpgFailure {
  let sql = "SELECT id, expr, total, target, outcome, rolled_by, context, created_at_ms FROM rolls WHERE session_id = ? ORDER BY id DESC LIMIT ?"
  let stmt = prepare(db, sql)
  stmt.bind_all([int_value(session_id), int_value(limit)]) |> ignore
  let rows : Array[RollRow] = []
  while stmt.step() {
    rows.push({
      id: stmt.column_int(0),
      expr: column_string(stmt, 1),
      total: stmt.column_int(2),
      target: column_opt_int(stmt, 3),
      outcome: column_string(stmt, 4),
      rolled_by: column_opt_string(stmt, 5),
      context: column_opt_string(stmt, 6),
      created_at_ms: column_int64(stmt, 7),
    })
  }
  finish_statement(stmt)
  rows.rev()
}

///|
fn recent_events(
  db : @sqlite.Database,
  session_id : Int,
  limit : Int,
) -> Array[EventRow] raise TrpgFailure {
  list_events(db, session_id, None, None, limit)
}

///|
fn list_events(
  db : @sqlite.Database,
  session_id : Int,
  kind : String?,
  actor : String?,
  limit : Int,
) -> Array[EventRow] raise TrpgFailure {
  let sql = match (kind, actor) {
    (Some(_), Some(_)) =>
      "SELECT id, session_id, kind, actor, subject, text, data_json, created_at_ms FROM events WHERE session_id = ? AND kind = ? AND actor = ? ORDER BY id DESC LIMIT ?"
    (Some(_), None) =>
      "SELECT id, session_id, kind, actor, subject, text, data_json, created_at_ms FROM events WHERE session_id = ? AND kind = ? ORDER BY id DESC LIMIT ?"
    (None, Some(_)) =>
      "SELECT id, session_id, kind, actor, subject, text, data_json, created_at_ms FROM events WHERE session_id = ? AND actor = ? ORDER BY id DESC LIMIT ?"
    (None, None) =>
      "SELECT id, session_id, kind, actor, subject, text, data_json, created_at_ms FROM events WHERE session_id = ? ORDER BY id DESC LIMIT ?"
  }
  let stmt = prepare(db, sql)
  let values : Array[@sqlite.SqlValue] = [int_value(session_id)]
  match kind {
    Some(value) => values.push(text_value(value))
    None => ()
  }
  match actor {
    Some(value) => values.push(text_value(value))
    None => ()
  }
  values.push(int_value(limit))
  stmt.bind_all(values) |> ignore
  let rows : Array[EventRow] = []
  while stmt.step() {
    rows.push({
      id: stmt.column_int(0),
      session_id: stmt.column_int(1),
      kind: column_string(stmt, 2),
      actor: column_opt_string(stmt, 3),
      subject: column_opt_string(stmt, 4),
      text: column_string(stmt, 5),
      data_json: column_string(stmt, 6),
      created_at_ms: column_int64(stmt, 7),
    })
  }
  finish_statement(stmt)
  rows.rev()
}

///|
fn scene_exists(
  db : @sqlite.Database,
  session_id : Int,
  key : String,
) -> Bool raise TrpgFailure {
  let stmt = prepare(
    db, "SELECT 1 FROM scenes WHERE session_id = ? AND key = ? LIMIT 1",
  )
  stmt.bind_all([int_value(session_id), text_value(key)]) |> ignore
  let exists = stmt.step()
  finish_statement(stmt)
  exists
}
