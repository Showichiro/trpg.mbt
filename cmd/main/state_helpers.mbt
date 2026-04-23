///|
fn normalize_ability(value : String) -> String raise TrpgFailure {
  match value {
    "body" | "tech" | "mind" => value
    _ =>
      fail(
        TrpgError::Usage(
          "unknown ability: \{value}",
          Some("supported abilities: body, tech, mind"),
        ),
      )
  }
}

///|
fn parse_modifier_spec(spec : String) -> (String, Int) raise TrpgFailure {
  match spec.split_once(":") {
    Some((ability_text, amount_text)) => {
      let ability = normalize_ability(ability_text.to_string())
      let raw_amount = amount_text.to_string()
      let normalized_amount = if raw_amount.has_prefix("+") {
        raw_amount[1:].to_string()
      } else {
        raw_amount
      }
      let amount = parse_int_arg(normalized_amount, "modifier amount")
      (ability, amount)
    }
    None =>
      fail(
        TrpgError::Usage(
          "invalid modifier: \{spec}",
          Some("use ability:+N, e.g. tech:+1"),
        ),
      )
  }
}

///|
fn normalize_modifier_spec(spec : String) -> String raise TrpgFailure {
  let (ability, amount) = parse_modifier_spec(spec)
  let amount_text = if amount >= 0 {
    "+" + amount.to_string()
  } else {
    amount.to_string()
  }
  ability + ":" + amount_text
}

///|
fn parse_sheet_object(
  source : String,
  label : String,
) -> Map[String, Json] raise TrpgFailure {
  match parse_json(source, label) {
    Object(object) => object
    _ =>
      fail(
        TrpgError::Usage(
          "expected JSON object in \{label}",
          Some("check the character sheet structure"),
        ),
      )
  }
}

///|
fn inventory_contains(items : Array[String], target : String) -> Bool {
  let mut found = false
  for item in items {
    if item == target {
      found = true
    }
  }
  found
}

///|
fn inventory_from_sheet_json(
  source : String,
) -> Array[String] raise TrpgFailure {
  let sheet = parse_sheet_object(source, "sheet_json")
  match sheet.get("inventory") {
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
fn traits_from_sheet_json(source : String) -> Array[String] raise TrpgFailure {
  let sheet = parse_sheet_object(source, "sheet_json")
  match sheet.get("traits") {
    Some(Array(items)) => {
      let out : Array[String] = []
      for item in items {
        match item {
          Object(object) => {
            let name = json_string_field(Json::object(object), "name", "trait")
            let desc = json_string_field(Json::object(object), "desc", "")
            if desc.is_empty() {
              out.push(name)
            } else {
              out.push("\{name}: \{desc}")
            }
          }
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
fn stat_from_sheet_json(
  source : String,
  ability : String,
) -> Int raise TrpgFailure {
  let normalized = normalize_ability(ability)
  let sheet = parse_sheet_object(source, "sheet_json")
  match sheet.get("stats") {
    Some(Object(stats)) =>
      match stats.get(normalized) {
        Some(Number(value, ..)) => value.to_int()
        _ => 0
      }
    _ => 0
  }
}

///|
fn add_inventory_item_json(
  source : String,
  item : String,
) -> String raise TrpgFailure {
  let sheet = parse_sheet_object(source, "sheet_json")
  let inventory = inventory_from_sheet_json(source)
  if inventory_contains(inventory, item) {
    fail(
      TrpgError::Conflict(
        "item already exists: \{item}",
        Some("use another item name or drop it first"),
      ),
    )
  }
  inventory.push(item)
  sheet["inventory"] = Json::array(inventory.map(value => Json::string(value)))
  Json::object(sheet).stringify()
}

///|
fn drop_inventory_item_json(
  source : String,
  item : String,
) -> String raise TrpgFailure {
  let sheet = parse_sheet_object(source, "sheet_json")
  let inventory = inventory_from_sheet_json(source)
  if !inventory_contains(inventory, item) {
    fail(
      TrpgError::NotFound(
        "item not found: \{item}",
        Some("use `trpg item list` to inspect current inventory"),
      ),
    )
  }
  let kept : Array[String] = []
  for value in inventory {
    if value != item {
      kept.push(value)
    }
  }
  sheet["inventory"] = Json::array(kept.map(value => Json::string(value)))
  Json::object(sheet).stringify()
}

///|
fn modifier_preview_from_condition(
  condition : Json,
  ability : String,
) -> ModifierPreviewRow? raise TrpgFailure {
  let normalized = normalize_ability(ability)
  match condition {
    Object(_) => {
      let modifier_spec = json_string_opt_field(condition, "modifier")
      match modifier_spec {
        Some(spec) => {
          let (modifier_ability, amount) = parse_modifier_spec(spec)
          if modifier_ability == normalized {
            Some({
              name: json_string_field(condition, "name", "status"),
              amount,
              uses: json_int_opt_field(condition, "uses"),
              duration: json_string_opt_field(condition, "duration"),
              on_trigger: json_string_opt_field(condition, "on_trigger"),
              note: json_string_field(condition, "note", ""),
            })
          } else {
            None
          }
        }
        None => None
      }
    }
    _ => None
  }
}

///|
fn roll_preview(
  row : CharacterRow,
  ability : String,
) -> RollPreview raise TrpgFailure {
  let normalized = normalize_ability(ability)
  let conditions = match parse_json(row.conditions_json, "conditions_json") {
    Array(items) => items
    _ => []
  }
  let modifiers : Array[ModifierPreviewRow] = []
  let mut auto_total = 0
  for condition in conditions {
    match modifier_preview_from_condition(condition, normalized) {
      Some(preview) => {
        auto_total += preview.amount
        modifiers.push(preview)
      }
      None => ()
    }
  }
  {
    ability: normalized,
    base_stat: stat_from_sheet_json(row.sheet_json, normalized),
    auto_total,
    modifiers,
    manual_traits: traits_from_sheet_json(row.sheet_json),
    inventory: inventory_from_sheet_json(row.sheet_json),
  }
}

///|
fn modifier_preview_json(row : ModifierPreviewRow) -> Json {
  let object : Map[String, Json] = {
    "name": Json::string(row.name),
    "amount": j_int(row.amount),
    "note": Json::string(row.note),
  }
  match row.uses {
    Some(value) => object["uses"] = j_int(value)
    None => ()
  }
  match row.duration {
    Some(value) => object["duration"] = Json::string(value)
    None => ()
  }
  match row.on_trigger {
    Some(value) => object["on_trigger"] = Json::string(value)
    None => ()
  }
  Json::object(object)
}

///|
fn roll_preview_json(preview : RollPreview) -> Json {
  Json::object({
    "ability": Json::string(preview.ability),
    "base_stat": j_int(preview.base_stat),
    "auto_modifier_total": j_int(preview.auto_total),
    "total_with_auto": j_int(preview.base_stat + preview.auto_total),
    "auto_modifiers": Json::array(preview.modifiers.map(modifier_preview_json)),
    "manual_traits": Json::array(
      preview.manual_traits.map(value => Json::string(value)),
    ),
    "inventory": Json::array(
      preview.inventory.map(value => Json::string(value)),
    ),
  })
}

///|
fn format_modifier_preview(row : ModifierPreviewRow) -> String {
  let amount_text = if row.amount >= 0 {
    "+" + row.amount.to_string()
  } else {
    row.amount.to_string()
  }
  let parts : Array[String] = ["\{row.name} \{amount_text}"]
  match row.uses {
    Some(value) => parts.push("uses=\{value}")
    None => ()
  }
  match row.duration {
    Some(value) if !value.is_empty() => parts.push("duration=\{value}")
    _ => ()
  }
  match row.on_trigger {
    Some(value) if !value.is_empty() => parts.push("on_trigger=\{value}")
    _ => ()
  }
  if !row.note.is_empty() {
    parts.push("note=\{row.note}")
  }
  parts.join(" / ")
}

///|
fn format_roll_preview(name : String, preview : RollPreview) -> String {
  let auto_total_text = if preview.auto_total >= 0 {
    "+" + preview.auto_total.to_string()
  } else {
    preview.auto_total.to_string()
  }
  let modifier_lines = if preview.modifiers.length() == 0 {
    "(なし)"
  } else {
    preview.modifiers.map(format_modifier_preview).join("\n- ")
  }
  let traits = if preview.manual_traits.length() == 0 {
    "(なし)"
  } else {
    preview.manual_traits.join("\n- ")
  }
  let inventory = if preview.inventory.length() == 0 {
    "(なし)"
  } else {
    preview.inventory.join(", ")
  }
  "\{name} \{preview.ability} 判定プレビュー\n" +
  "能力値: \{preview.base_stat}\n" +
  "自動修正合計: \{auto_total_text}\n" +
  "合計(能力値+自動修正): \{preview.base_stat + preview.auto_total}\n" +
  "自動修正:\n- " +
  modifier_lines +
  "\n手動判断の trait:\n- " +
  traits +
  "\n所持品: " +
  inventory
}
