///|
test "play style round trips through sheet json" {
  let source = "{\"name\":\"alice\",\"inventory\":[],\"traits\":[],\"stats\":{\"body\":1,\"tech\":2,\"mind\":0}}"
  let styled = set_play_style_json(
    source,
    require_catalog_play_style("schemer"),
  )
  let style = play_style_from_sheet_json(styled).unwrap_or(
    require_catalog_play_style("wildcard"),
  )
  inspect(style.id, content="schemer")
  inspect(style.display_name, content="策士")
}

///|
test "play style formatter is concise in brief mode" {
  let style = require_catalog_play_style("supportive")
  inspect(
    format_play_style_prompt(style, true),
    content="援護役 [supportive] - 味方への援護、情報整理、段取りを優先する。\nこの傾向は行動提案の方向性だけに効く。協力前提とルール順守は崩さない。",
  )
}

///|
test "unknown stored play style falls back to generic profile" {
  let source = "{\"name\":\"alice\",\"play_style\":{\"id\":\"custom_style\"},\"inventory\":[],\"traits\":[],\"stats\":{\"body\":1,\"tech\":2,\"mind\":0}}"
  let style = play_style_from_sheet_json(source).unwrap_or(
    require_catalog_play_style("wildcard"),
  )
  inspect(style.id, content="custom_style")
  inspect(style.cooperation_mode, content="cooperative")
}
