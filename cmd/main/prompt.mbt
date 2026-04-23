///|
const RULES_TEXT : String =
  #|# ルール要約
  #|
  #|- 判定は `2d6 + 修正値 >= 目標値`。
  #|- 難易度は易 7 / 並 9 / 難 11。
  #|- 能力値は body / tech / mind。traits は GM が文脈で判断する。
  #|- 数値判定は必ず `trpg roll`、HP 変動は必ず `trpg hp`、状態は必ず `trpg status` を使う。
  #|- プレイヤーは 1 ターンに 1 行動だけ宣言し、自分で数値結果を決めない。

///|
fn dispatch_prompt(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let role = need_pos(positions, 1, "prompt role")
  match role {
    "gm" => prompt_gm(global)
    "player" => prompt_player(global)
    "rules" => {
      let json = Json::object({
        "command": "prompt.rules",
        "text": Json::string(RULES_TEXT),
      })
      output_success(
        { json, human: RULES_TEXT, stderr: "ルールプロンプトを出力" },
        global,
      )
    }
    _ =>
      fail(
        TrpgError::Usage(
          "unknown prompt role: \{role}",
          Some("supported roles: gm, player, rules"),
        ),
      )
  }
}

///|
fn prompt_gm(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let scenario = load_scenario_json(session.scenario_id)
  let prompt = compose_gm_prompt(db, session, scenario)
  let json = Json::object({
    "command": "prompt.gm",
    "text": Json::string(prompt),
  })
  output_success(
    { json, human: prompt, stderr: "GM プロンプトを出力" },
    global,
  )
}

///|
fn prompt_player(global : GlobalArgs) -> RunResult raise TrpgFailure {
  let positions = positional_args(global.args)
  let name = need_pos(positions, 2, "player name")
  let db = open_db()
  defer db.close()
  let session = require_active_session(db)
  let row = require_character(db, session.id, name)
  let scenario = load_scenario_json(session.scenario_id)
  let characters = list_characters(db, session.id)
  let history = recent_history(db, session.id, 12)
  let prompt = "あなたは TRPG セッションのプレイヤーです。\n\n" +
    "与えられた PC を演じ、1 ターンに 1 つだけ自然な日本語で行動宣言してください。\n" +
    "数値判定・ダメージ・成功失敗は決めず、必要なら GM に判定を促してください。\n\n" +
    "## セッション\n" +
    "現在シーン: \{session.current_scene}\n" +
    current_scene_description(scenario, session.current_scene) +
    "\n\n" +
    "## PC\n" +
    row.sheet_json +
    "\n\n" +
    "現在 HP: \{row.hp_cur}/\{row.hp_max}\n" +
    "状態: \{row.conditions_json}\n\n" +
    "## パーティ状態\n" +
    format_characters_for_prompt(characters) +
    "\n\n" +
    "## 直近履歴\n" +
    format_history_for_prompt(history)
  let json = Json::object({
    "command": "prompt.player",
    "name": Json::string(name),
    "text": Json::string(prompt),
  })
  output_success(
    { json, human: prompt, stderr: "Player プロンプトを出力: \{name}" },
    global,
  )
}

///|
fn compose_gm_prompt(
  db : @sqlite.Database,
  session : SessionRow,
  scenario : Json,
) -> String raise TrpgFailure {
  let title = json_string_field(scenario, "title", session.scenario_id)
  let summary = json_string_field(scenario, "summary", "")
  let scene_description = current_scene_description(
    scenario,
    session.current_scene,
  )
  let pcs = list_characters(db, session.id)
  let history = recent_history(db, session.id, 16)
  "あなたはファンタジー世界の GM です。質実剛健で、必要な場面だけ叙情的に描写してください。\n\n" +
  "## セッション\n" +
  "シナリオ: " +
  title +
  "\n" +
  "概要: " +
  summary +
  "\n" +
  "現在シーン: " +
  session.current_scene +
  "\n" +
  scene_description +
  "\n\n" +
  "## ルール\n" +
  RULES_TEXT +
  "\n\n" +
  "## PC/NPC 状態\n" +
  format_characters_for_prompt(pcs) +
  "\n\n" +
  "## 直近履歴\n" +
  format_history_for_prompt(history) +
  "\n\n" +
  "## GM 手順\n" +
  "- 判定が必要なときは `trpg roll 2d6+修正値 --target N --as 名前 --context \"状況\"` を実行し、JSON の `outcome` を引用する。\n" +
  "- HP 変動は `trpg hp 名前 -3 --context \"理由\"` のように CLI で更新する。\n" +
  "- 状態は `trpg status 名前 add 毒 --note \"効果量/継続条件/消費トリガー\"` のように CLI で更新する。\n" +
  "- シーン転換時は `trpg session scene <id> [--note \"変化\"]` を使う。\n" +
  "- アイテム獲得・喪失は `trpg item give/drop 名前 アイテム名 [--note \"理由\"]` を使う。\n" +
  "- 描写の最後に、次に行動する相手を明示して「あなたの番です」と振る。"
}

///|
fn current_scene_description(scenario : Json, key : String) -> String {
  match json_get(scenario, "scenes") {
    Some(Object(scenes)) =>
      match scenes.get(key) {
        Some(scene) => {
          let desc = json_string_field(scene, "description", "")
          let hint = json_string_field(scene, "difficulty_hint", "")
          if hint.is_empty() {
            desc
          } else {
            desc + "\n難易度目安: " + hint
          }
        }
        None => ""
      }
    _ => ""
  }
}

///|
fn format_characters_for_prompt(rows : Array[CharacterRow]) -> String {
  if rows.length() == 0 {
    "(未登録)"
  } else {
    rows
    .map(row => {
      "- \{row.name} [\{row.kind}] HP \{row.hp_cur}/\{row.hp_max} conditions=\{row.conditions_json}"
    })
    .join("\n")
  }
}
