///|
fn json_semantically_equal(left : Json, right : Json) -> Bool {
  match left {
    Null =>
      match right {
        Null => true
        _ => false
      }
    True =>
      match right {
        True => true
        _ => false
      }
    False =>
      match right {
        False => true
        _ => false
      }
    String(a) =>
      match right {
        String(b) => a == b
        _ => false
      }
    Number(a, ..) =>
      match right {
        Number(b, ..) => a == b
        _ => false
      }
    Array(xs) =>
      match right {
        Array(ys) => {
          if xs.length() != ys.length() {
            return false
          }
          for i in 0..<xs.length() {
            if !json_semantically_equal(xs[i], ys[i]) {
              return false
            }
          }
          true
        }
        _ => false
      }
    Object(xs) =>
      match right {
        Object(ys) => {
          if xs.length() != ys.length() {
            return false
          }
          for key, value in xs {
            match ys.get(key) {
              Some(other) =>
                if !json_semantically_equal(value, other) {
                  return false
                }
              None => return false
            }
          }
          true
        }
        _ => false
      }
  }
}

///|
fn repo_scenario_ids() -> Array[String] raise TrpgFailure {
  let names = @fs.read_dir("scenarios") catch {
    err =>
      fail(
        TrpgError::Permission(
          "failed to read scenarios directory",
          Some(err.to_string()),
        ),
      )
  }
  let ids = names
    .filter(name => name.has_suffix(".json") && !name.has_prefix("sample_pc_"))
    .map(strip_json_suffix)
  ids.sort()
  ids
}

///|
fn repo_template_ids() -> Array[String] raise TrpgFailure {
  let prefix = "sample_pc_"
  let names = @fs.read_dir("scenarios") catch {
    err =>
      fail(
        TrpgError::Permission(
          "failed to read scenarios directory",
          Some(err.to_string()),
        ),
      )
  }
  let ids = names
    .filter(name => name.has_suffix(".json") && name.has_prefix(prefix))
    .map(name => strip_json_suffix(name[prefix.length():].to_string()))
  ids.sort()
  ids
}

///|
test "bundled scenario ids stay in sync with repo scenario files" {
  let bundled = bundled_scenario_ids()
  bundled.sort()
  let repo = repo_scenario_ids()
  inspect(bundled, content=repo.to_string())
}

///|
test "bundled scenario payloads stay in sync with repo scenario files" {
  for id in repo_scenario_ids() {
    let bundled = match bundled_scenario_source(id) {
      Some(source) => source.scenario
      None => panic()
    }
    let path = "scenarios/\{id}.json"
    let repo = parse_json(read_text_file(path), path)
    inspect(json_semantically_equal(bundled, repo), content="true")
  }
}

///|
test "bundled template ids stay in sync with repo template files" {
  let bundled : Array[String] = []
  for id in repo_scenario_ids() {
    let scenario = match bundled_scenario_source(id) {
      Some(source) => source.scenario
      None => panic()
    }
    for template_id in scenario_sample_pc_ids(scenario) {
      if !bundled.contains(template_id) {
        bundled.push(template_id)
      }
    }
  }
  bundled.sort()
  let repo = repo_template_ids()
  inspect(bundled, content=repo.to_string())
}

///|
test "bundled template payloads stay in sync with repo template files" {
  for id in repo_template_ids() {
    let text = match bundled_template_text(id) {
      Some(text) => text
      None => panic()
    }
    let bundled = parse_json(text, "bundled template: \{id}")
    let path = "scenarios/sample_pc_\{id}.json"
    let repo = parse_json(read_text_file(path), path)
    inspect(json_semantically_equal(bundled, repo), content="true")
  }
}
