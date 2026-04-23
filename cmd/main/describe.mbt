///|
fn command_descriptor(summary : String, usage : String) -> Json {
  Json::object({ "summary": summary, "usage": usage })
}

///|
fn describe_commands_json() -> Json {
  Json::object({
    "name": "trpg",
    "version": VERSION,
    "commands": Json::object({
      "session.init": command_descriptor(
        "セッションを開始する", "trpg session init <scenario_id> [--if-not-exists]",
      ),
      "session.show": command_descriptor(
        "アクティブセッションを表示する", "trpg session show",
      ),
      "session.end": command_descriptor(
        "アクティブセッションを終了する", "trpg session end",
      ),
      "session.scene": command_descriptor(
        "現在シーンを変更する", "trpg session scene <key> [--note text]",
      ),
      "session.note": command_descriptor(
        "GM メモをログに残す", "trpg session note <text>",
      ),
      "pc.add": command_descriptor(
        "PC を登録する", "trpg pc add <name> --from <path>",
      ),
      "pc.show": command_descriptor(
        "PC/NPC を表示する", "trpg pc show <name> [--for-roll body|tech|mind]",
      ),
      "roll": command_descriptor(
        "ダイスを振る", "trpg roll <expr> [--target N] [--as name] [--context text]",
      ),
      "hp": command_descriptor(
        "HP を増減する", "trpg hp <name> <delta> [--by actor] [--context text]",
      ),
      "status": command_descriptor(
        "状態タグを追加・削除する", "trpg status <name> <add|remove> <tag> [--note text] [--modifier ability:+N] [--uses N] [--duration text] [--on-trigger consume|persist]",
      ),
      "item.give": command_descriptor(
        "アイテムを付与する", "trpg item give <name> <item> [--note text]",
      ),
      "item.drop": command_descriptor(
        "アイテムを削除する", "trpg item drop <name> <item> [--note text]",
      ),
      "item.list": command_descriptor(
        "インベントリを表示する", "trpg item list [<name>]",
      ),
      "log.add": command_descriptor(
        "ログを追加する", "trpg log add <text> --as <actor>",
      ),
      "log.tail": command_descriptor(
        "ログ末尾を表示する", "trpg log tail [-n N]",
      ),
      "scene.set": command_descriptor(
        "現在シーンを変更する (session.scene の互換 alias)", "trpg scene set <key> [--note text]",
      ),
      "scene.flag": command_descriptor(
        "現在シーンのフラグを設定する", "trpg scene flag <key> <value>",
      ),
      "scenario.show": command_descriptor(
        "シナリオ定義を表示する", "trpg scenario show <scenario_id>",
      ),
      "prompt.gm": command_descriptor(
        "GM 用プロンプトを合成する", "trpg prompt gm [--human]",
      ),
      "prompt.player": command_descriptor(
        "Player 用プロンプトを合成する", "trpg prompt player <name> [--human]",
      ),
      "prompt.rules": command_descriptor(
        "ルール要約を出力する", "trpg prompt rules [--human]",
      ),
    }),
    "exit_codes": Json::object({
      "0": "success",
      "1": "general_error",
      "2": "usage_error",
      "3": "resource_not_found",
      "4": "permission_denied",
      "5": "conflict",
    }),
  })
}
