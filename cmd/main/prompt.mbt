///|
const RULES_TEXT : String =
  #|# ルール要約
  #|
  #|- 判定は `2d6 + 修正値 >= 目標値`。
  #|- 難易度は易 7 / 並 9 / 難 11。
  #|- 能力値は body / tech / mind。actor-aware `trpg roll <name> --stat ...` は能力値を修正値に加算する。
  #|- traits / inventory item / status は `effect.stat == --stat` かつ tag が一致したときだけ自動適用される。GM は必要に応じて場面 tag を追加してよいが、custom tag を足すと既存 trait/item/status の tag 一致が外れて auto apply が減ることがある。
  #|- 搦め手で scene の難易度を流用するときは `trpg roll <name> --scene-default --stat <other>` を優先する。準備・援護は原則 `trpg roll <name> --prep --stat <body|tech|mind>` を使う。`--prep` は target 未指定時に現在 scene の target を 2 下げ、scene target が無いときは 9 を使う。scene target を個別変更したいときだけ `--target N` を明示する。
  #|- 準備や援護の成功は `trpg roll orion --prep --grant-to alice --grant tech:+1@ritual,seal` のように一時 status を自動付与してよい。`--grant-to` に自分自身を指定して self-grant してもよい。手動なら `trpg status 名前 add --name 効果名 --source 援護者 --modifier tech:+1 --tags ritual,seal --uses 1 --on-trigger consume` を使う。本命ロールの stat に合わせて積む。
  #|- 数値判定は必ず `trpg roll`、HP 変動は必ず `trpg hp`、状態は必ず `trpg status` を使う。
  #|- goal に `scene_flag(...)` がある場合は `trpg scene flag` で進捗を更新する。
  #|- 長い障害や repeated near miss は `trpg scene progress <key> <delta>` を使って累積進捗を残してよい。同じ障害で 2 連続 near miss なら progress を 1 残し、3 連続なら `trpg scene modifier add --name "扉が緩む" --next-roll target:-2 --stat tech --tags forced-entry` のように次判定を 1 段階易化してよい。`duration=scene` の status は scene 遷移時に自動で消える。
  #|- near miss / fumble / 強制進行の裁定は `trpg session note "HP 半減適用" --kind soften --ref-event 37` のように対応する event に紐づけて残してよい。
  #|- `special=crit` は難度 1 段階軽減相当、または `+2〜+3 / uses=1` の援護 status、または副次好機 1 つの目安として扱う。`special=fumble` は一段重く扱う。
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
  let brief = flag_present(global.args, "--brief")
  let prompt = compose_gm_prompt(db, session, scenario, brief)
  let json = Json::object({
    "command": "prompt.gm",
    "brief": Json::boolean(brief),
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
  let brief = flag_present(global.args, "--brief")
  let history_limit = if brief { 5 } else { 12 }
  let history = recent_history(db, session.id, history_limit)
  let prompt = "あなたは TRPG セッションのプレイヤーです。\n\n" +
    "与えられた PC を演じ、1 ターンに 1 つだけ自然な日本語で行動宣言してください。\n" +
    "数値判定・ダメージ・成功失敗は決めず、必要なら GM に判定を促してください。\n\n" +
    "## セッション\n" +
    "現在シーン: \{session.current_scene}\n" +
    current_scene_description(scenario, session.current_scene) +
    "\n\n" +
    "## PC\n" +
    format_player_character_prompt(row, brief) +
    "\n\n" +
    "## パーティ状態\n" +
    format_characters_for_prompt(characters, brief) +
    "\n\n" +
    "## 直近履歴\n" +
    format_history_for_prompt(history)
  let json = Json::object({
    "command": "prompt.player",
    "name": Json::string(name),
    "brief": Json::boolean(brief),
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
  brief : Bool,
) -> String raise TrpgFailure {
  let title = json_string_field(scenario, "title", session.scenario_id)
  let summary = json_string_field(scenario, "summary", "")
  let scene_description = current_scene_description(
    scenario,
    session.current_scene,
  )
  let pcs = list_characters(db, session.id)
  let history = recent_history(db, session.id, if brief { 5 } else { 16 })
  let goals = goal_statuses(db, session, scenario)
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
  format_characters_for_prompt(pcs, brief) +
  "\n\n" +
  "## 現在の goals\n" +
  format_goal_statuses(goals) +
  "\n\n" +
  "## 直近履歴\n" +
  format_history_for_prompt(history) +
  "\n\n" +
  "## GM 手順\n" +
  "- 判定が必要なときは `trpg roll 名前 --scene-default --stat tech --tags lockpick --context \"状況\"` のように actor-aware roll を使い、JSON の `outcome` / `margin` / `special` を引用する。準備・援護は `--prep` を優先し、scene target を個別変更したいときだけ `--target N` を明示する。\n" +
  "- HP 変動は `trpg hp 名前 -3 --context \"理由\"` のように CLI で更新する。\n" +
  "- 状態は `trpg status 名前 add --name 毒 --source 司書の亡霊 --note \"効果量/継続条件/消費トリガー\" --modifier tech:-2 --tags ritual,seal --uses 1 --on-trigger consume` のように CLI で更新する。準備や援護は `--grant-to` / `--grant` で自動付与してよく、self-grant してもよい。\n" +
  "- シーン転換時は `trpg session scene <id> [--note \"変化\"]` を使う。\n" +
  "- 同じ障害で 2 連続 near miss なら、`trpg scene progress obstacle +1 --note \"扉が緩む\"` のように累積進捗を残す。3 連続なら `trpg scene modifier add --name \"扉が緩む\" --next-roll target:-2 --stat tech --tags forced-entry` のように次判定を 1 段階易化してよい。\n" +
  "- near miss / fumble / 強制進行の裁定は `trpg session note \"HP 半減適用\" --kind soften --ref-event 37` のように対応 event に紐づけて残してよい。\n" +
  "- goal に `scene_flag(...)` がある場合は `trpg scene flag <key> <value>` を打つ。途中確認は `trpg session goals` を使う。\n" +
  "- アイテム獲得・喪失は `trpg item give/drop 名前 アイテム名 [--note \"理由\"]`、受け渡しは `trpg item transfer A B アイテム名 [--note \"理由\"]` を使う。\n" +
  "- NPC の対抗判定は `trpg contest`、攻撃は `trpg attack` を使う。\n" +
  "- 描写の最後に、次に行動する相手を明示して「あなたの番です」と振る。"
}

///|
fn format_character_sheet_summary(row : CharacterRow) -> String {
  let sheet = parse_json(row.sheet_json, "sheet_json") catch {
    _ => Json::object({})
  }
  let class_name = json_string_field(sheet, "class", "")
  let class_text = if class_name.is_empty() {
    ""
  } else {
    " class=\{class_name}"
  }
  let stats_text = match json_get(sheet, "stats") {
    Some(Object(stats)) => {
      let stats_json = Json::object(stats)
      let body = json_int_field(stats_json, "body", 0)
      let tech = json_int_field(stats_json, "tech", 0)
      let mind = json_int_field(stats_json, "mind", 0)
      "body=\{body} tech=\{tech} mind=\{mind}"
    }
    _ => "body=0 tech=0 mind=0"
  }
  let items = inventory_from_sheet_json(row.sheet_json) catch { _ => [] }
  let items_text = if items.length() == 0 {
    "(なし)"
  } else {
    items.join(", ")
  }
  let conditions_text = format_conditions_human(row.conditions_json) catch {
    _ => row.conditions_json
  }
  "\{row.name} [\{row.kind}]\{class_text} \{stats_text} HP=\{row.hp_cur}/\{row.hp_max} items=\{items_text} conditions=\{conditions_text}"
}

///|
fn format_player_character_prompt(row : CharacterRow, brief : Bool) -> String {
  let conditions_text = format_conditions_human(row.conditions_json) catch {
    _ => row.conditions_json
  }
  if brief {
    format_character_sheet_summary(row)
  } else {
    row.sheet_json +
    "\n\n" +
    "現在 HP: \{row.hp_cur}/\{row.hp_max}\n" +
    "状態: \{conditions_text}"
  }
}

///|
fn format_characters_for_prompt(
  rows : Array[CharacterRow],
  brief : Bool,
) -> String {
  if rows.length() == 0 {
    "(未登録)"
  } else {
    rows
    .map(row => {
      let conditions_text = format_conditions_human(row.conditions_json) catch {
        _ => row.conditions_json
      }
      if brief {
        "- " + format_character_sheet_summary(row)
      } else {
        "- \{row.name} [\{row.kind}] HP \{row.hp_cur}/\{row.hp_max} conditions=\{conditions_text}"
      }
    })
    .join("\n")
  }
}
