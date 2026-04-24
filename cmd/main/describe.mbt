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
      "session.goals": command_descriptor(
        "現在の goal 達成状況を表示する", "trpg session goals",
      ),
      "session.end": command_descriptor(
        "アクティブセッションを終了する", "trpg session end [--outcome success|failure|partial]",
      ),
      "session.report": command_descriptor(
        "セッションの要約を表示する", "trpg session report",
      ),
      "session.scene": command_descriptor(
        "現在シーンを変更する", "trpg session scene <key> [--note text]",
      ),
      "session.note": command_descriptor(
        "GM メモをログに残す", "trpg session note <text>",
      ),
      "pc.add": command_descriptor(
        "PC を登録する", "trpg pc add <name> (--from <path> | --template <template_id>)",
      ),
      "pc.show": command_descriptor(
        "PC/NPC を表示する", "trpg pc show <name> [--for-roll body|tech|mind] [--tags lockpick,ritual]",
      ),
      "pc.templates.list": command_descriptor(
        "利用可能な PC template を表示する", "trpg pc templates list",
      ),
      "roll": command_descriptor(
        "ダイスを振る", "trpg roll <expr> [--target N] [--as name] [--context text] | trpg roll <name> --stat <body|tech|mind> [--bonus N] [--target N|--scene-default|--prep] [--tags tag1,tag2] [--grant-to <name> --grant <ability:+N@tag1,tag2> [--grant-name <status_name>]] [--context text]",
      ),
      "roll.history": command_descriptor(
        "判定履歴を表示する", "trpg roll history [--as name] [-n N]",
      ),
      "contest": command_descriptor(
        "対抗判定を実行する", "trpg contest <actor_a> <actor_b> --a-stat <stat> --b-stat <stat> [--a-tags tag1,tag2] [--b-tags tag1,tag2] [--a-bonus N] [--b-bonus N] [--context text]",
      ),
      "attack": command_descriptor(
        "攻撃判定を実行する", "trpg attack <attacker> <defender> --atk <stat> --def <stat> --damage <expr> [--atk-tags tag1,tag2] [--def-tags tag1,tag2] [--atk-bonus N] [--def-bonus N] [--context text]",
      ),
      "hp": command_descriptor(
        "HP を増減する", "trpg hp <name> <delta> [--by actor] [--context text]",
      ),
      "status": command_descriptor(
        "状態タグを追加・削除する", "trpg status <character> add --name <status_name> [--source actor] [--note text] [--modifier ability:+N] [--tags tag1,tag2] [--uses N] [--duration text] [--on-trigger consume|persist] | trpg status <character> remove <status_name>",
      ),
      "item.give": command_descriptor(
        "アイテムを付与する", "trpg item give <name> <item> [--desc text] [--effect ability:+N] [--tags tag1,tag2] [--note text]",
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
      "log.show": command_descriptor(
        "イベント履歴を表示する", "trpg log show [--by actor] [--kind kind] [-n N]",
      ),
      "scene.set": command_descriptor(
        "現在シーンを変更する (session.scene の互換 alias)", "trpg scene set <key> [--note text]",
      ),
      "scene.list": command_descriptor(
        "シーン一覧と遷移候補を表示する", "trpg scene list",
      ),
      "scene.show": command_descriptor(
        "現在シーンまたは指定シーンを表示する", "trpg scene show [<key>]",
      ),
      "scene.next": command_descriptor(
        "遷移候補が1件なら次シーンへ進む", "trpg scene next [--note text]",
      ),
      "scene.flag": command_descriptor(
        "現在シーンのフラグを設定する (goal 条件の進行に使う)",
        "trpg scene flag <key> <value>",
      ),
      "scenario.show": command_descriptor(
        "シナリオ定義を表示する", "trpg scenario show <scenario_id>",
      ),
      "scenario.validate": command_descriptor(
        "シナリオ定義を検証する", "trpg scenario validate <scenario_id>",
      ),
      "prompt.gm": command_descriptor(
        "GM 用プロンプトを合成する", "trpg prompt gm [--brief] [--human]",
      ),
      "prompt.player": command_descriptor(
        "Player 用プロンプトを合成する", "trpg prompt player <name> [--brief] [--human]",
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
