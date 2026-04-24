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
fn parse_tags_csv(source : String?) -> Array[String] {
  match source {
    Some(text) => {
      let tags : Array[String] = []
      for chunk in text.split(",") {
        let tag = chunk.trim().to_string()
        if !tag.is_empty() && !string_array_contains(tags, tag) {
          tags.push(tag)
        }
      }
      tags
    }
    None => []
  }
}

///|
fn string_array_contains(items : Array[String], target : String) -> Bool {
  let mut found = false
  for item in items {
    if item == target {
      found = true
    }
  }
  found
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
fn object_name(value : Json, fallback : String) -> String {
  json_string_field(value, "name", fallback)
}

///|
fn item_objects_from_sheet_json(
  source : String,
) -> Array[Json] raise TrpgFailure {
  let sheet = parse_sheet_object(source, "sheet_json")
  match sheet.get("inventory") {
    Some(Array(items)) => {
      let out : Array[Json] = []
      for item in items {
        match item {
          Object(object) => out.push(Json::object(object))
          String(value) =>
            out.push(
              Json::object({
                "id": Json::string(value),
                "name": Json::string(value),
                "effects": Json::array([]),
              }),
            )
          _ => ()
        }
      }
      out
    }
    _ => []
  }
}

///|
fn trait_objects_from_sheet_json(
  source : String,
) -> Array[Json] raise TrpgFailure {
  let sheet = parse_sheet_object(source, "sheet_json")
  match sheet.get("traits") {
    Some(Array(items)) => {
      let out : Array[Json] = []
      for item in items {
        match item {
          Object(object) => out.push(Json::object(object))
          String(value) =>
            out.push(
              Json::object({
                "id": Json::string(value),
                "name": Json::string(value),
                "effects": Json::array([]),
              }),
            )
          _ => ()
        }
      }
      out
    }
    _ => []
  }
}

///|
fn inventory_from_sheet_json(
  source : String,
) -> Array[String] raise TrpgFailure {
  item_objects_from_sheet_json(source).map(item => object_name(item, "item"))
}

///|
fn effect_tags(effect : Json) -> Array[String] {
  json_string_array_field(effect, "tags")
}

///|
fn effect_trigger(effect : Json) -> String {
  json_string_field(effect, "trigger", "roll")
}

///|
fn effect_stat_name(
  effect : Json,
  ability : String,
) -> String raise TrpgFailure {
  normalize_ability(json_string_field(effect, "stat", ability))
}

///|
fn tags_match(
  effect_tags : Array[String],
  requested_tags : Array[String],
) -> Bool {
  if effect_tags.length() == 0 || string_array_contains(effect_tags, "all") {
    true
  } else if requested_tags.length() == 0 {
    false
  } else {
    let mut matched = false
    for tag in requested_tags {
      if string_array_contains(effect_tags, tag) {
        matched = true
      }
    }
    matched
  }
}

///|
fn effect_skip_reason(
  effect : Json,
  ability : String,
  requested_tags : Array[String],
) -> String? raise TrpgFailure {
  let trigger = effect_trigger(effect)
  if trigger != "roll" {
    Some("trigger_mismatch")
  } else {
    let effect_stat = effect_stat_name(effect, ability)
    if effect_stat != ability {
      Some("stat_mismatch")
    } else if !tags_match(effect_tags(effect), requested_tags) {
      Some("tag_mismatch")
    } else {
      None
    }
  }
}

///|
fn modifier_preview_row(
  kind : String,
  name : String,
  effect : Json,
  note : String,
  uses : Int?,
  duration : String?,
  on_trigger : String?,
) -> ModifierPreviewRow {
  {
    kind,
    name,
    amount: json_int_field(effect, "amount", 0),
    tags: effect_tags(effect),
    uses,
    duration,
    on_trigger,
    note,
  }
}

///|
fn skipped_modifier_row(
  kind : String,
  name : String,
  effect : Json,
  reason : String,
  ability : String,
  requested_tags : Array[String],
) -> SkippedModifierRow raise TrpgFailure {
  {
    kind,
    name,
    reason,
    effect_stat: effect_stat_name(effect, ability),
    requested_stat: ability,
    effect_tags: effect_tags(effect),
    requested_tags,
    effect_trigger: effect_trigger(effect),
  }
}

///|
fn trait_modifiers(
  source : String,
  ability : String,
  tags : Array[String],
) -> ModifierResolution raise TrpgFailure {
  let matched : Array[ModifierPreviewRow] = []
  let skipped : Array[SkippedModifierRow] = []
  for trait_row in trait_objects_from_sheet_json(source) {
    let name = object_name(trait_row, "trait")
    let note = json_string_field(trait_row, "desc", "")
    for effect in json_array_field(trait_row, "effects") {
      match effect_skip_reason(effect, ability, tags) {
        Some(reason) =>
          skipped.push(
            skipped_modifier_row("trait", name, effect, reason, ability, tags),
          )
        None =>
          matched.push(
            modifier_preview_row("trait", name, effect, note, None, None, None),
          )
      }
    }
  }
  { matched, skipped }
}

///|
fn item_modifiers(
  source : String,
  ability : String,
  tags : Array[String],
) -> ModifierResolution raise TrpgFailure {
  let matched : Array[ModifierPreviewRow] = []
  let skipped : Array[SkippedModifierRow] = []
  for item in item_objects_from_sheet_json(source) {
    let name = object_name(item, "item")
    let note = json_string_field(item, "desc", "")
    for effect in json_array_field(item, "effects") {
      match effect_skip_reason(effect, ability, tags) {
        Some(reason) =>
          skipped.push(
            skipped_modifier_row("item", name, effect, reason, ability, tags),
          )
        None =>
          matched.push(
            modifier_preview_row("item", name, effect, note, None, None, None),
          )
      }
    }
  }
  { matched, skipped }
}

///|
fn legacy_status_effect(condition : Json) -> Json? raise TrpgFailure {
  match json_string_opt_field(condition, "modifier") {
    Some(spec) => {
      let (ability, amount) = parse_modifier_spec(spec)
      Some(
        Json::object({
          "stat": Json::string(ability),
          "amount": j_int(amount),
          "tags": Json::array([]),
          "trigger": Json::string("roll"),
        }),
      )
    }
    None => None
  }
}

///|
fn status_modifiers(
  source : String,
  ability : String,
  tags : Array[String],
) -> ModifierResolution raise TrpgFailure {
  let matched : Array[ModifierPreviewRow] = []
  let skipped : Array[SkippedModifierRow] = []
  let conditions = match parse_json(source, "conditions_json") {
    Array(items) => items
    _ => []
  }
  for condition in conditions {
    let name = json_string_field(condition, "name", "status")
    let note = json_string_field(condition, "note", "")
    let uses = json_int_opt_field(condition, "uses")
    let duration = json_string_opt_field(condition, "duration")
    let on_trigger = json_string_opt_field(condition, "on_trigger")
    let effects = if json_array_field(condition, "effects").length() > 0 {
      json_array_field(condition, "effects")
    } else {
      match legacy_status_effect(condition) {
        Some(effect) => [effect]
        None => []
      }
    }
    for effect in effects {
      match effect_skip_reason(effect, ability, tags) {
        Some(reason) =>
          skipped.push(
            skipped_modifier_row("status", name, effect, reason, ability, tags),
          )
        None =>
          matched.push(
            modifier_preview_row(
              "status", name, effect, note, uses, duration, on_trigger,
            ),
          )
      }
    }
  }
  { matched, skipped }
}

///|
fn matching_modifiers(
  row : CharacterRow,
  ability : String,
  tags : Array[String],
) -> ModifierResolution raise TrpgFailure {
  let matched : Array[ModifierPreviewRow] = []
  let skipped : Array[SkippedModifierRow] = []
  let trait_rows = trait_modifiers(row.sheet_json, ability, tags)
  for item in trait_rows.matched {
    matched.push(item)
  }
  for item in trait_rows.skipped {
    skipped.push(item)
  }
  let item_rows = item_modifiers(row.sheet_json, ability, tags)
  for item in item_rows.matched {
    matched.push(item)
  }
  for item in item_rows.skipped {
    skipped.push(item)
  }
  let status_rows = status_modifiers(row.conditions_json, ability, tags)
  for item in status_rows.matched {
    matched.push(item)
  }
  for item in status_rows.skipped {
    skipped.push(item)
  }
  { matched, skipped }
}

///|
fn unique_strings(values : Array[String]) -> Array[String] {
  let out : Array[String] = []
  for value in values {
    if !string_array_contains(out, value) {
      out.push(value)
    }
  }
  out
}

///|
fn consume_statuses_json(
  source : String,
  consumed_names : Array[String],
) -> String raise TrpgFailure {
  let conditions = match parse_json(source, "conditions_json") {
    Array(items) => items
    _ => []
  }
  let counters : Map[String, Int] = {}
  for name in consumed_names {
    let next = match counters.get(name) {
      Some(value) => value + 1
      None => 1
    }
    counters[name] = next
  }
  let kept : Array[Json] = []
  for condition in conditions {
    let name = json_string_field(condition, "name", "")
    let remaining = match counters.get(name) {
      Some(value) => value
      None => 0
    }
    if remaining == 0 {
      kept.push(condition)
    } else {
      counters[name] = remaining - 1
      let on_trigger = json_string_field(condition, "on_trigger", "")
      let uses = json_int_opt_field(condition, "uses")
      if on_trigger == "consume" {
        match uses {
          Some(value) if value > 1 =>
            match condition {
              Object(object) => {
                object["uses"] = j_int(value - 1)
                kept.push(Json::object(object))
              }
              _ => ()
            }
          Some(1) => ()
          None => ()
          _ => kept.push(condition)
        }
      } else {
        kept.push(condition)
      }
    }
  }
  Json::array(kept).stringify()
}

///|
fn effect_json(
  ability : String,
  amount : Int,
  tags : Array[String],
  trigger : String,
) -> Json {
  Json::object({
    "stat": Json::string(ability),
    "amount": j_int(amount),
    "tags": Json::array(tags.map(value => Json::string(value))),
    "trigger": Json::string(trigger),
  })
}

///|
fn make_inventory_item_json(
  name : String,
  desc : String?,
  effect_spec : String?,
  tags : Array[String],
) -> Json raise TrpgFailure {
  let item : Map[String, Json] = {
    "id": Json::string(name),
    "name": Json::string(name),
    "effects": Json::array([]),
  }
  match desc {
    Some(value) if !value.is_empty() => item["desc"] = Json::string(value)
    _ => ()
  }
  match effect_spec {
    Some(spec) => {
      let (ability, amount) = parse_modifier_spec(spec)
      item["effects"] = Json::array([effect_json(ability, amount, tags, "roll")])
    }
    None => ()
  }
  Json::object(item)
}

///|
fn add_inventory_item_json(
  source : String,
  item : String,
  desc : String?,
  effect_spec : String?,
  tags : Array[String],
) -> String raise TrpgFailure {
  let sheet = parse_sheet_object(source, "sheet_json")
  let inventory = item_objects_from_sheet_json(source)
  let names = inventory.map(current => object_name(current, "item"))
  if string_array_contains(names, item) {
    fail(
      TrpgError::Conflict(
        "item already exists: \{item}",
        Some("use another item name or drop it first"),
      ),
    )
  }
  inventory.push(make_inventory_item_json(item, desc, effect_spec, tags))
  sheet["inventory"] = Json::array(inventory)
  Json::object(sheet).stringify()
}

///|
fn drop_inventory_item_json(
  source : String,
  item : String,
) -> String raise TrpgFailure {
  let sheet = parse_sheet_object(source, "sheet_json")
  let inventory = item_objects_from_sheet_json(source)
  let kept : Array[Json] = []
  let mut found = false
  for value in inventory {
    if object_name(value, "item") == item {
      found = true
    } else {
      kept.push(value)
    }
  }
  if !found {
    fail(
      TrpgError::NotFound(
        "item not found: \{item}",
        Some("use `trpg item list` to inspect current inventory"),
      ),
    )
  }
  sheet["inventory"] = Json::array(kept)
  Json::object(sheet).stringify()
}

///|
fn roll_preview(
  row : CharacterRow,
  ability : String,
  tags : Array[String],
) -> RollPreview raise TrpgFailure {
  let normalized = normalize_ability(ability)
  let resolution = matching_modifiers(row, normalized, tags)
  let mut auto_total = 0
  for modifier in resolution.matched {
    auto_total += modifier.amount
  }
  {
    ability: normalized,
    base_stat: stat_from_sheet_json(row.sheet_json, normalized),
    auto_total,
    modifiers: resolution.matched,
    skipped_modifiers: resolution.skipped,
    inventory: inventory_from_sheet_json(row.sheet_json),
  }
}

///|
fn actor_roll(
  row : CharacterRow,
  ability : String,
  bonus : Int,
  target : Int?,
  tags : Array[String],
  scene_warning : String?,
) -> ActorRollRow raise TrpgFailure {
  let preview = roll_preview(row, ability, tags)
  let total_modifier = preview.base_stat + preview.auto_total + bonus
  let sign = if total_modifier > 0 {
    "+" + total_modifier.to_string()
  } else if total_modifier < 0 {
    total_modifier.to_string()
  } else {
    ""
  }
  let expr = "2d6" + sign
  let evaluated = eval_dice(expr)
  let margin = roll_margin(evaluated.total, target)
  let special = roll_special(evaluated.rolls)
  let consumed_statuses = unique_strings(
    preview.modifiers
    .filter(source => {
      source.kind == "status" && source.on_trigger == Some("consume")
    })
    .map(source => source.name),
  )
  {
    actor: row.name,
    ability: preview.ability,
    base_stat: preview.base_stat,
    auto_modifier_total: preview.auto_total,
    bonus,
    total_modifier,
    target,
    expr,
    total: evaluated.total,
    rolls: evaluated.rolls,
    outcome: roll_outcome(evaluated.total, target),
    margin,
    special,
    modifiers: preview.modifiers,
    skipped_modifiers: preview.skipped_modifiers,
    consumed_statuses,
    scene_warning,
  }
}

///|
fn modifier_preview_json(row : ModifierPreviewRow) -> Json {
  let object : Map[String, Json] = {
    "kind": Json::string(row.kind),
    "name": Json::string(row.name),
    "amount": j_int(row.amount),
    "tags": Json::array(row.tags.map(value => Json::string(value))),
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
fn skipped_modifier_json(row : SkippedModifierRow) -> Json {
  Json::object({
    "kind": Json::string(row.kind),
    "name": Json::string(row.name),
    "reason": Json::string(row.reason),
    "effect_stat": Json::string(row.effect_stat),
    "requested_stat": Json::string(row.requested_stat),
    "effect_tags": Json::array(
      row.effect_tags.map(value => Json::string(value)),
    ),
    "requested_tags": Json::array(
      row.requested_tags.map(value => Json::string(value)),
    ),
    "effect_trigger": Json::string(row.effect_trigger),
  })
}

///|
fn roll_preview_json(preview : RollPreview) -> Json {
  Json::object({
    "ability": Json::string(preview.ability),
    "base_stat": j_int(preview.base_stat),
    "auto_modifier_total": j_int(preview.auto_total),
    "total_with_auto": j_int(preview.base_stat + preview.auto_total),
    "auto_modifiers": Json::array(preview.modifiers.map(modifier_preview_json)),
    "skipped_sources": Json::array(
      preview.skipped_modifiers.map(skipped_modifier_json),
    ),
    "inventory": Json::array(
      preview.inventory.map(value => Json::string(value)),
    ),
  })
}

///|
fn actor_roll_json(row : ActorRollRow) -> Json {
  let object : Map[String, Json] = {
    "actor": Json::string(row.actor),
    "ability": Json::string(row.ability),
    "base_stat": j_int(row.base_stat),
    "auto_modifier_total": j_int(row.auto_modifier_total),
    "bonus": j_int(row.bonus),
    "total_modifier": j_int(row.total_modifier),
    "modifier_total": j_int(row.total_modifier),
    "expr": Json::string(row.expr),
    "total": j_int(row.total),
    "rolls": json_int_array(row.rolls),
    "outcome": Json::string(row.outcome),
    "special": Json::string(row.special),
    "sources": Json::array(row.modifiers.map(modifier_preview_json)),
    "skipped_sources": Json::array(
      row.skipped_modifiers.map(skipped_modifier_json),
    ),
    "consumed_statuses": Json::array(
      row.consumed_statuses.map(value => Json::string(value)),
    ),
  }
  match row.target {
    Some(value) => object["target"] = j_int(value)
    None => object["target"] = Json::null()
  }
  match row.margin {
    Some(value) => object["margin"] = j_int(value)
    None => object["margin"] = Json::null()
  }
  match row.scene_warning {
    Some(value) => object["scene_warning"] = Json::string(value)
    None => ()
  }
  Json::object(object)
}

///|
fn format_modifier_preview(row : ModifierPreviewRow) -> String {
  let amount_text = if row.amount >= 0 {
    "+" + row.amount.to_string()
  } else {
    row.amount.to_string()
  }
  let tags_text = if row.tags.length() == 0 {
    ""
  } else {
    "tags=" + row.tags.join(",")
  }
  let parts : Array[String] = ["[\{row.kind}] \{row.name} \{amount_text}"]
  if !tags_text.is_empty() {
    parts.push(tags_text)
  }
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
fn format_skipped_modifier(row : SkippedModifierRow) -> String {
  let effect_tags_text = if row.effect_tags.length() == 0 {
    "(none)"
  } else {
    row.effect_tags.join(",")
  }
  let requested_tags_text = if row.requested_tags.length() == 0 {
    "(none)"
  } else {
    row.requested_tags.join(",")
  }
  let reason_text = match row.reason {
    "stat_mismatch" =>
      "stat_mismatch \{row.effect_stat} vs \{row.requested_stat}"
    "tag_mismatch" =>
      "tag_mismatch effect_tags=\{effect_tags_text} requested_tags=\{requested_tags_text}"
    "trigger_mismatch" => "trigger_mismatch trigger=\{row.effect_trigger}"
    _ => row.reason
  }
  "[\{row.kind}] \{row.name} / \{reason_text}"
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
    "- " + preview.modifiers.map(format_modifier_preview).join("\n- ")
  }
  let inventory = if preview.inventory.length() == 0 {
    "(なし)"
  } else {
    preview.inventory.join(", ")
  }
  let skipped = if preview.skipped_modifiers.length() == 0 {
    "(なし)"
  } else {
    "- " + preview.skipped_modifiers.map(format_skipped_modifier).join("\n- ")
  }
  "\{name} \{preview.ability} 判定プレビュー\n" +
  "能力値: \{preview.base_stat}\n" +
  "自動修正合計: \{auto_total_text}\n" +
  "合計(能力値+自動修正): \{preview.base_stat + preview.auto_total}\n" +
  "自動修正:\n" +
  modifier_lines +
  "\nskipped_sources:\n" +
  skipped +
  "\n所持品: " +
  inventory
}

///|
fn format_actor_roll(row : ActorRollRow) -> String {
  let target_text = match row.target {
    Some(value) => " / target=\{value}"
    None => ""
  }
  let margin_text = match row.margin {
    Some(value) => " / margin=\{value}"
    None => ""
  }
  let special_text = if row.special == "none" {
    ""
  } else {
    " / special=\{row.special}"
  }
  let warning_text = match row.scene_warning {
    Some(value) if !value.is_empty() => "\nwarning: \{value}"
    _ => ""
  }
  let sources = if row.modifiers.length() == 0 {
    "(なし)"
  } else {
    "- " + row.modifiers.map(format_modifier_preview).join("\n- ")
  }
  let consumed = if row.consumed_statuses.length() == 0 {
    "(なし)"
  } else {
    row.consumed_statuses.join(", ")
  }
  let skipped = if row.skipped_modifiers.length() == 0 {
    "(なし)"
  } else {
    "- " + row.skipped_modifiers.map(format_skipped_modifier).join("\n- ")
  }
  "\{row.actor} \{row.expr} = \{row.total}\{target_text} / \{row.outcome}\{margin_text}\{special_text}\n" +
  "base_stat=\{row.base_stat} auto_modifier_total=\{row.auto_modifier_total} bonus=\{row.bonus} total_modifier=\{row.total_modifier}\n" +
  "sources:\n" +
  sources +
  "\nskipped_sources:\n" +
  skipped +
  "\nconsumed_statuses: " +
  consumed +
  warning_text
}
