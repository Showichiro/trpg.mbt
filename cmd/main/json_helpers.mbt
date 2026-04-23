///|
fn j_int(value : Int) -> Json {
  Json::number(value.to_double())
}

///|
fn j_i64(value : Int64) -> Json {
  Json::number(value.to_double())
}

///|
fn json_int_array(values : Array[Int]) -> Json {
  Json::array(values.map(value => j_int(value)))
}

///|
fn parse_json(source : String, label : String) -> Json raise TrpgFailure {
  let parsed : Result[Json, _] = try? @json.parse(source)
  match parsed {
    Ok(value) => value
    Err(err) =>
      fail(
        TrpgError::Usage(
          "invalid JSON in \{label}: \{err}",
          Some("check the JSON syntax"),
        ),
      )
  }
}

///|
fn json_get(json : Json, key : String) -> Json? {
  match json {
    Object(object) => object.get(key)
    _ => None
  }
}

///|
fn json_string(json : Json) -> String? {
  match json {
    String(value) => Some(value)
    _ => None
  }
}

///|
fn json_int(json : Json) -> Int? {
  match json {
    Number(value, ..) => Some(value.to_int())
    _ => None
  }
}

///|
fn json_string_field(json : Json, key : String, fallback : String) -> String {
  match json_get(json, key) {
    Some(value) =>
      match json_string(value) {
        Some(text) => text
        None => fallback
      }
    None => fallback
  }
}

///|
fn json_int_field(json : Json, key : String, fallback : Int) -> Int {
  match json_get(json, key) {
    Some(value) =>
      match json_int(value) {
        Some(n) => n
        None => fallback
      }
    None => fallback
  }
}

///|
fn json_string_opt_field(json : Json, key : String) -> String? {
  match json_get(json, key) {
    Some(value) => json_string(value)
    None => None
  }
}

///|
fn json_int_opt_field(json : Json, key : String) -> Int? {
  match json_get(json, key) {
    Some(value) => json_int(value)
    None => None
  }
}

///|
fn json_string_array_field(json : Json, key : String) -> Array[String] {
  match json_get(json, key) {
    Some(Array(items)) => {
      let out : Array[String] = []
      for item in items {
        match item {
          String(value) => out.push(value)
          _ => ()
        }
      }
      out
    }
    _ => []
  }
}

///|
fn bytes_to_string(bytes : Bytes) -> String {
  @utf8.decode_lossy(bytes)
}

///|
fn now_ms() -> Int64 {
  @env.now().reinterpret_as_int64()
}
