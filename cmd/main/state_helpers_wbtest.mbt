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
  let added = add_inventory_item_json(source, "銀の鍵")
  inspect(
    inventory_from_sheet_json(added),
    content="[\"短剣\", \"縄\", \"銀の鍵\"]",
  )
  let dropped = drop_inventory_item_json(added, "縄")
  inspect(
    inventory_from_sheet_json(dropped),
    content="[\"短剣\", \"銀の鍵\"]",
  )
}

///|
test "roll preview sums only matching structured modifiers" {
  let row : CharacterRow = {
    id: 1,
    name: "alice",
    kind: "pc",
    sheet_json: "{\"name\":\"alice\",\"inventory\":[\"短剣\"],\"traits\":[{\"name\":\"錠開け\",\"desc\":\"解錠で +1\"}],\"stats\":{\"body\":1,\"tech\":2,\"mind\":0}}",
    hp_cur: 8,
    hp_max: 8,
    conditions_json: "[{\"name\":\"祝福\",\"note\":\"次の解錠判定 +2\",\"modifier\":\"tech:+2\",\"uses\":1,\"on_trigger\":\"consume\"},{\"name\":\"疲労\",\"note\":\"体判定 -1\",\"modifier\":\"body:-1\"}]",
  }
  let preview = roll_preview(row, "tech")
  inspect(preview.base_stat, content="2")
  inspect(preview.auto_total, content="2")
  inspect(preview.modifiers.length(), content="1")
  inspect(
    format_modifier_preview(preview.modifiers[0]),
    content="祝福 +2 / uses=1 / on_trigger=consume / note=次の解錠判定 +2",
  )
  inspect(preview.manual_traits, content="[\"錠開け: 解錠で +1\"]")
  inspect(preview.inventory, content="[\"短剣\"]")
  inspect(
    format_roll_preview("alice", preview),
    content="alice tech 判定プレビュー\n能力値: 2\n自動修正合計: +2\n合計(能力値+自動修正): 4\n自動修正:\n- 祝福 +2 / uses=1 / on_trigger=consume / note=次の解錠判定 +2\n手動判断の trait:\n- 錠開け: 解錠で +1\n所持品: 短剣",
  )
}
