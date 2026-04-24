///|
fn scenario_meta_path(id : String) -> String raise TrpgFailure {
  scenarios_dir() + "/" + id + ".meta.json"
}

///|
fn is_scenario_url(value : String) -> Bool {
  value.has_prefix("http://") || value.has_prefix("https://")
}

///|
fn is_scenario_path(value : String) -> Bool {
  @fs.path_exists(value) ||
  value.has_prefix("/") ||
  value.has_prefix("./") ||
  value.has_prefix("../") ||
  value.contains("/") ||
  value.has_suffix(".json")
}

///|
fn trim_query_and_fragment(value : String) -> String {
  let mut end = value.length()
  match value.find("?") {
    Some(index) => end = index
    None => ()
  }
  match value.find("#") {
    Some(index) if index < end => end = index
    _ => ()
  }
  value[:end].to_string()
}

///|
fn basename_from_path(value : String) -> String {
  let cleaned = trim_query_and_fragment(value)
  match cleaned.rev_find("/") {
    Some(index) => cleaned[index + 1:].to_string()
    None => cleaned
  }
}

///|
fn strip_json_suffix(value : String) -> String {
  if value.has_suffix(".json") {
    value[:value.length() - 5].to_string()
  } else {
    value
  }
}

///|
fn scenario_id_from_json_or_fallback(
  scenario : Json,
  fallback : String,
) -> String raise TrpgFailure {
  let id = json_string_field(scenario, "id", fallback)
  let id = if id.is_empty() { fallback } else { id }
  if id.is_empty() || id.contains("/") || id.contains("\\") {
    fail(
      TrpgError::Usage(
        "invalid scenario id: \{id}",
        Some("scenario id must be a non-empty file-safe string"),
      ),
    )
  } else {
    id
  }
}

///|
fn scenario_install_meta_json(
  origin : String,
  source_url : String?,
  installed_at_ms : Int64,
) -> Json {
  let object : Map[String, Json] = {
    "origin": Json::string(origin),
    "installed_at_ms": j_i64(installed_at_ms),
  }
  match source_url {
    Some(value) => object["source_url"] = Json::string(value)
    None => object["source_url"] = Json::null()
  }
  Json::object(object)
}

///|
fn write_text_file(path : String, content : String) -> Unit raise TrpgFailure {
  @fs.write_string_to_file(path, content) catch {
    err =>
      fail(
        TrpgError::Permission(
          "failed to write file: \{path}",
          Some(err.to_string()),
        ),
      )
  }
}

///|
fn remove_file_if_exists(path : String) -> Unit raise TrpgFailure {
  if @fs.path_exists(path) {
    @fs.remove_file(path) catch {
      err =>
        fail(
          TrpgError::Permission(
            "failed to remove file: \{path}",
            Some(err.to_string()),
          ),
        )
    }
  }
}

///|
fn load_scenario_install_meta(id : String) -> Json? raise TrpgFailure {
  let path = scenario_meta_path(id)
  if !@fs.path_exists(path) {
    None
  } else {
    let source = read_text_file(path)
    Some(parse_json(source, path))
  }
}

///|
fn scenario_origin(meta : Json?) -> String {
  match meta {
    Some(value) => json_string_field(value, "origin", "local")
    None => "local"
  }
}

///|
fn scenario_source_url(meta : Json?) -> String? {
  match meta {
    Some(value) => json_string_opt_field(value, "source_url")
    None => None
  }
}

///|
fn scenario_installed_at_ms(meta : Json?) -> Int64? {
  match meta {
    Some(value) =>
      match json_int_opt_field(value, "installed_at_ms") {
        Some(ms) => Some(ms.to_int64())
        None => None
      }
    None => None
  }
}

///|
fn scenario_install_row(
  id : String,
  path : String,
  scenario : Json,
  meta : Json?,
) -> ScenarioInstallRow {
  {
    id,
    title: json_string_field(scenario, "title", id),
    summary: json_string_field(scenario, "summary", ""),
    version: json_string_opt_field(scenario, "version"),
    path,
    origin: scenario_origin(meta),
    source_url: scenario_source_url(meta),
    installed_at_ms: scenario_installed_at_ms(meta),
  }
}

///|
fn scenario_install_row_json(row : ScenarioInstallRow) -> Json {
  let object : Map[String, Json] = {
    "id": Json::string(row.id),
    "title": Json::string(row.title),
    "summary": Json::string(row.summary),
    "path": Json::string(row.path),
    "origin": Json::string(row.origin),
  }
  match row.version {
    Some(value) => object["version"] = Json::string(value)
    None => object["version"] = Json::null()
  }
  match row.source_url {
    Some(value) => object["source_url"] = Json::string(value)
    None => object["source_url"] = Json::null()
  }
  match row.installed_at_ms {
    Some(value) => object["installed_at_ms"] = j_i64(value)
    None => object["installed_at_ms"] = Json::null()
  }
  Json::object(object)
}

///|
fn format_scenario_install_row(row : ScenarioInstallRow) -> String {
  let parts : Array[String] = ["- \{row.id}: \{row.title}"]
  if !row.summary.is_empty() {
    parts.push("  summary: \{row.summary}")
  }
  parts.push("  path: \{row.path}")
  parts.push("  origin: \{row.origin}")
  match row.version {
    Some(value) if !value.is_empty() => parts.push("  version: \{value}")
    _ => ()
  }
  match row.source_url {
    Some(value) if !value.is_empty() => parts.push("  source_url: \{value}")
    _ => ()
  }
  parts.join("\n")
}

///|
fn list_installed_scenarios() -> Array[ScenarioInstallRow] raise TrpgFailure {
  ensure_home_dirs()
  let names = @fs.read_dir(scenarios_dir()) catch {
    err =>
      fail(
        TrpgError::Permission(
          "failed to read scenarios directory",
          Some(err.to_string()),
        ),
      )
  }
  names.sort()
  let rows : Array[ScenarioInstallRow] = []
  for name in names {
    if !name.has_suffix(".json") || name.has_suffix(".meta.json") {
      continue
    }
    let id = strip_json_suffix(name)
    let path = scenarios_dir() + "/" + name
    try {
      let scenario = parse_json(read_text_file(path), path)
      ignore(validate_scenario_json(scenario, id))
      let meta = load_scenario_install_meta(id)
      rows.push(scenario_install_row(id, path, scenario, meta))
    } catch {
      TrpgFailure(_) => ()
    }
  }
  rows
}

///|
fn require_installed_scenario(
  id : String,
) -> ScenarioInstallRow raise TrpgFailure {
  for row in list_installed_scenarios() {
    if row.id == id {
      return row
    }
  }
  fail(
    TrpgError::NotFound(
      "scenario is not installed: \{id}",
      Some("run `trpg scenario list` or `trpg scenario import <url-or-path>`"),
    ),
  )
}

///|
async fn fetch_scenario_text(url : String) -> String raise TrpgFailure {
  let (response, body) = @async.with_timeout(10000, () => @http.get(url)) catch {
    err =>
      fail(
        TrpgError::General(
          "failed to fetch scenario: \{url}",
          Some(err.to_string()),
        ),
      )
  }
  if response.code == 404 {
    fail(
      TrpgError::NotFound(
        "scenario url returned 404: \{url}",
        Some("check the URL"),
      ),
    )
  }
  if response.code < 200 || response.code >= 300 {
    fail(
      TrpgError::General(
        "scenario fetch failed: HTTP \{response.code}",
        Some(url),
      ),
    )
  }
  body.text() catch {
    err =>
      fail(
        TrpgError::General(
          "failed to read scenario response body: \{url}",
          Some(err.to_string()),
        ),
      )
  }
}

///|
async fn load_scenario_source(
  value : String,
) -> ScenarioSourceRow raise TrpgFailure {
  if is_scenario_url(value) {
    let text = fetch_scenario_text(value)
    let scenario = parse_json(text, value)
    let fallback = strip_json_suffix(basename_from_path(value))
    let scenario_id = scenario_id_from_json_or_fallback(scenario, fallback)
    {
      scenario_id,
      source_kind: "url",
      source_label: value,
      source_text: text,
      scenario,
      source_url: Some(value),
    }
  } else if is_scenario_path(value) {
    if !@fs.path_exists(value) {
      fail(
        TrpgError::NotFound(
          "scenario file is not found: \{value}",
          Some("check the path"),
        ),
      )
    }
    let text = read_text_file(value)
    let scenario = parse_json(text, value)
    let fallback = strip_json_suffix(basename_from_path(value))
    let scenario_id = scenario_id_from_json_or_fallback(scenario, fallback)
    {
      scenario_id,
      source_kind: "path",
      source_label: value,
      source_text: text,
      scenario,
      source_url: None,
    }
  } else {
    let scenario = load_scenario_json(value)
    {
      scenario_id: value,
      source_kind: "installed",
      source_label: scenario_path(value),
      source_text: read_text_file(scenario_path(value)),
      scenario,
      source_url: scenario_source_url(load_scenario_install_meta(value)),
    }
  }
}

///|
fn ensure_scenario_write_allowed(
  id : String,
  allow_replace : Bool,
) -> Unit raise TrpgFailure {
  let target_path = scenario_path(id)
  if @fs.path_exists(target_path) && !allow_replace {
    fail(
      TrpgError::Conflict(
        "scenario already exists: \{id}",
        Some("pass `--force` to replace the installed scenario"),
      ),
    )
  }
  let db = open_db()
  defer db.close()
  match active_session(db) {
    Some(session) if session.scenario_id == id =>
      fail(
        TrpgError::Conflict(
          "cannot replace active scenario: \{id}",
          Some("end the active session before replacing the scenario"),
        ),
      )
    _ => ()
  }
}

///|
fn ensure_scenario_remove_allowed(id : String) -> Unit raise TrpgFailure {
  let db = open_db()
  defer db.close()
  match active_session(db) {
    Some(session) if session.scenario_id == id =>
      fail(
        TrpgError::Conflict(
          "cannot remove active scenario: \{id}",
          Some("end the active session before removing the scenario"),
        ),
      )
    _ => ()
  }
}

///|
fn install_scenario_source(
  source : ScenarioSourceRow,
  allow_replace : Bool,
) -> ScenarioInstallRow raise TrpgFailure {
  validate_scenario_json(source.scenario, source.scenario_id)
  ensure_scenario_write_allowed(source.scenario_id, allow_replace)
  ensure_home_dirs()
  let target_path = scenario_path(source.scenario_id)
  write_text_file(target_path, source.source_text)
  let installed_at_ms = now_ms()
  let meta = scenario_install_meta_json(
    "imported",
    source.source_url,
    installed_at_ms,
  )
  write_text_file(scenario_meta_path(source.scenario_id), meta.stringify())
  scenario_install_row(
    source.scenario_id,
    target_path,
    source.scenario,
    Some(meta),
  )
}
