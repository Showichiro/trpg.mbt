///|
test "positional args skip newly added option values" {
  let args = [
    "pc", "show", "alice", "--for-roll", "tech", "--modifier", "tech:+1", "--uses",
    "1", "--duration", "scene", "--on-trigger", "consume",
  ]
  inspect(positional_args(args), content="[\"pc\", \"show\", \"alice\"]")
}

///|
test "inventory helpers add and drop items" {
  let source = "{\"name\":\"alice\",\"inventory\":[\"短剣\",\"縄\"],\"traits\":[],\"stats\":{\"body\":1,\"tech\":2,\"mind\":0}}"
  let added = add_inventory_item_json(source, "銀の鍵", None, None, [])
  inspect(
    inventory_from_sheet_json(added),
    content="[\"短剣\", \"縄\", \"銀の鍵\"]",
  )
  let dropped = drop_inventory_item_json(added, "縄")
  inspect(
    inventory_from_sheet_json(dropped),
    content="[\"短剣\", \"銀の鍵\"]",
  )
  let (without_key, key_item) = take_inventory_item_json(added, "銀の鍵")
  let transferred = add_existing_inventory_item_json(
    "{\"name\":\"orion\",\"inventory\":[],\"traits\":[],\"stats\":{\"body\":0,\"tech\":1,\"mind\":2}}",
    key_item,
  )
  inspect(
    inventory_from_sheet_json(without_key),
    content="[\"短剣\", \"縄\"]",
  )
  inspect(inventory_from_sheet_json(transferred), content="[\"銀の鍵\"]")
}

///|
test "inventory transfer can retag and rewrite effect" {
  let item = Json::object({
    "id": Json::string("銀の鍵"),
    "name": Json::string("銀の鍵"),
    "effects": Json::array([
      Json::object({
        "stat": Json::string("tech"),
        "amount": j_int(1),
        "tags": Json::array([Json::string("lockpick")]),
        "trigger": Json::string("roll"),
      }),
    ]),
  })
  let updated = update_inventory_item_json(
    item,
    ["ritual", "seal"],
    Some("mind:+1"),
  )
  inspect(
    updated.stringify(),
    content="{\"id\":\"銀の鍵\",\"name\":\"銀の鍵\",\"effects\":[{\"stat\":\"mind\",\"amount\":1,\"tags\":[\"lockpick\",\"ritual\",\"seal\"],\"trigger\":\"roll\"}]}",
  )
}

///|
test "modifier-with-tags spec parses support shorthand" {
  inspect(
    parse_modifier_with_tags_spec("tech:+1@ritual,seal"),
    content="(\"tech\", 1, [\"ritual\", \"seal\"])",
  )
  inspect(parse_modifier_with_tags_spec("mind:+2"), content="(\"mind\", 2, [])")
}

///|
test "scene duration conditions expire on transition" {
  let source = "[{\"name\":\"動揺\",\"duration\":\"scene\",\"effects\":[{\"stat\":\"body\",\"amount\":-1,\"tags\":[\"forced-entry\"],\"trigger\":\"roll\"}]},{\"name\":\"祝福\",\"uses\":1,\"effects\":[{\"stat\":\"tech\",\"amount\":1,\"tags\":[\"seal\"],\"trigger\":\"roll\"}]}]"
  let (next_conditions, expired) = expire_scene_duration_conditions(source)
  inspect(expired, content="[\"動揺\"]")
  inspect(
    format_conditions_human(next_conditions),
    content="祝福 (tech+1 @ seal, uses=1)",
  )
}

///|
test "humanized conditions include source and tags" {
  let source = "[{\"name\":\"斜光援護\",\"source\":\"orion\",\"uses\":1,\"effects\":[{\"stat\":\"tech\",\"amount\":1,\"tags\":[\"ritual\",\"seal\"],\"trigger\":\"roll\"}]},{\"name\":\"動揺\",\"note\":\"足がすくむ\"}]"
  inspect(
    format_conditions_human(source),
    content="斜光援護 (tech+1 @ ritual,seal, from orion, uses=1); 動揺 (足がすくむ)",
  )
}

///|
test "roll preview sums only matching structured modifiers" {
  let row : CharacterRow = {
    id: 1,
    name: "alice",
    kind: "pc",
    sheet_json: "{\"name\":\"alice\",\"inventory\":[\"短剣\"],\"traits\":[{\"name\":\"錠開け\",\"desc\":\"解錠で +1\",\"effects\":[{\"stat\":\"tech\",\"amount\":1,\"tags\":[\"lockpick\"],\"trigger\":\"roll\"}]},{\"name\":\"古文書読解\",\"desc\":\"儀式文脈で +1\",\"effects\":[{\"stat\":\"mind\",\"amount\":1,\"tags\":[\"ritual\",\"seal\"],\"trigger\":\"roll\"}]}],\"stats\":{\"body\":1,\"tech\":2,\"mind\":0}}",
    hp_cur: 8,
    hp_max: 8,
    conditions_json: "[{\"name\":\"祝福\",\"note\":\"次の解錠判定 +2\",\"source\":\"orion\",\"effects\":[{\"stat\":\"tech\",\"amount\":2,\"tags\":[\"lockpick\"],\"trigger\":\"roll\"}],\"uses\":1,\"on_trigger\":\"consume\"},{\"name\":\"疲労\",\"note\":\"体判定 -1\",\"modifier\":\"body:-1\"},{\"name\":\"封印補助\",\"note\":\"封印判定 +1\",\"effects\":[{\"stat\":\"tech\",\"amount\":1,\"tags\":[\"seal\"],\"trigger\":\"roll\"}],\"uses\":1}]",
  }
  let preview = roll_preview(row, "tech", ["lockpick"])
  inspect(preview.base_stat, content="2")
  inspect(preview.auto_total, content="3")
  inspect(preview.modifiers.length(), content="2")
  inspect(preview.skipped_modifiers.length(), content="3")
  inspect(
    format_modifier_preview(preview.modifiers[0]),
    content="[trait] 錠開け +1 / tags=lockpick / note=解錠で +1",
  )
  inspect(
    format_modifier_preview(preview.modifiers[1]),
    content="[status] 祝福 +2 / tags=lockpick / source=orion / uses=1 / on_trigger=consume / note=次の解錠判定 +2",
  )
  inspect(
    format_skipped_modifier(preview.skipped_modifiers[0]),
    content="[trait] 古文書読解 / stat_mismatch mind vs tech",
  )
  inspect(
    format_skipped_modifier(preview.skipped_modifiers[2]),
    content="[status] 封印補助 / tag_mismatch effect_tags=seal requested_tags=lockpick",
  )
  inspect(preview.inventory, content="[\"短剣\"]")
  inspect(
    format_roll_preview("alice", preview),
    content="alice tech 判定プレビュー\n能力値: 2\n自動修正合計: +3\n合計(能力値+自動修正): 5\n自動修正:\n- [trait] 錠開け +1 / tags=lockpick / note=解錠で +1\n- [status] 祝福 +2 / tags=lockpick / source=orion / uses=1 / on_trigger=consume / note=次の解錠判定 +2\nskipped_sources:\n- [trait] 古文書読解 / stat_mismatch mind vs tech\n- [status] 疲労 / stat_mismatch body vs tech\n- [status] 封印補助 / tag_mismatch effect_tags=seal requested_tags=lockpick\n所持品: 短剣",
  )
}

///|
test "roll preview can skip named status without consuming it" {
  let row : CharacterRow = {
    id: 1,
    name: "alice",
    kind: "pc",
    sheet_json: "{\"name\":\"alice\",\"inventory\":[],\"traits\":[],\"stats\":{\"body\":1,\"tech\":2,\"mind\":0}}",
    hp_cur: 8,
    hp_max: 8,
    conditions_json: "[{\"name\":\"把握した鍵の留め具\",\"effects\":[{\"stat\":\"tech\",\"amount\":2,\"tags\":[\"lockpick\"],\"trigger\":\"roll\"}],\"uses\":1,\"on_trigger\":\"consume\"}]",
  }
  let preview = roll_preview_with_skips(row, "tech", ["lockpick"], [
    "把握した鍵の留め具",
  ])
  inspect(preview.auto_total, content="0")
  inspect(preview.modifiers.length(), content="0")
  inspect(preview.skipped_modifiers.length(), content="1")
  inspect(
    format_skipped_modifier(preview.skipped_modifiers[0]),
    content="[status] 把握した鍵の留め具 / manually_skipped",
  )
}

///|
test "actor roll includes base stat in total modifier" {
  let row : CharacterRow = {
    id: 1,
    name: "alice",
    kind: "pc",
    sheet_json: "{\"name\":\"alice\",\"inventory\":[],\"traits\":[{\"name\":\"錠開け\",\"desc\":\"解錠で +1\",\"effects\":[{\"stat\":\"tech\",\"amount\":1,\"tags\":[\"lockpick\"],\"trigger\":\"roll\"}]}],\"stats\":{\"body\":1,\"tech\":2,\"mind\":0}}",
    hp_cur: 8,
    hp_max: 8,
    conditions_json: "[{\"name\":\"祝福\",\"note\":\"次の解錠判定 +2\",\"effects\":[{\"stat\":\"tech\",\"amount\":2,\"tags\":[\"lockpick\"],\"trigger\":\"roll\"}],\"uses\":1,\"on_trigger\":\"consume\"}]",
  }
  let rolled = actor_roll(row, "tech", 1, Some(11), ["lockpick"], [], 0, None)
  inspect(rolled.base_stat, content="2")
  inspect(rolled.auto_modifier_total, content="3")
  inspect(rolled.bonus, content="1")
  inspect(rolled.total_modifier, content="6")
  inspect(rolled.expr, content="2d6+6")
  inspect(rolled.margin != None, content="true")
  inspect(rolled.skipped_modifiers.length(), content="0")
}

///|
test "scene modifiers apply to matching next roll and then consume" {
  let modifiers : Array[SceneModifierRow] = [
    {
      name: "扉が緩む",
      target_delta: -2,
      stat: Some("tech"),
      tags: ["forced-entry"],
      note: "蝶番が軋む",
      source: Some("gm"),
      scope: "next_roll",
    },
  ]
  let (target, delta, applied, remaining) = apply_scene_modifiers(
    modifiers,
    "tech",
    ["forced-entry"],
    Some(9),
  )
  inspect(target, content="Some(7)")
  inspect(delta, content="-2")
  inspect(applied.length(), content="1")
  inspect(remaining.length(), content="0")
  inspect(
    format_scene_modifier(applied[0]),
    content="扉が緩む / target -2 / stat=tech / tags=forced-entry / source=gm / note=蝶番が軋む",
  )
}

///|
test "scene modifiers stay when stat or tags do not match" {
  let modifiers : Array[SceneModifierRow] = [
    {
      name: "扉が緩む",
      target_delta: -2,
      stat: Some("tech"),
      tags: ["forced-entry"],
      note: "",
      source: None,
      scope: "next_roll",
    },
  ]
  let (target, delta, applied, remaining) = apply_scene_modifiers(
    modifiers,
    "mind",
    ["forced-entry"],
    Some(9),
  )
  inspect(target, content="Some(9)")
  inspect(delta, content="0")
  inspect(applied.length(), content="0")
  inspect(remaining.length(), content="1")
}
