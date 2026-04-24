---
description: TRPG セッションの振り返りレポートを Markdown の読み物として保存する
---

TRPG retrospective skill を使って、最新または active session の振り返りレポートを Markdown で作成してください。

- まず `.claude/skills/trpg-retrospective/scripts/export_session_context.py` を実行して、対象 session と保存先候補を取得してください。
- 次に `trpg session report --human` を見て、人間向けの短い要約を補助情報として使ってください。
- 同じ会話内に今回の GM narration や subagent の `private_handoff_text` / `非公開意図` が残っていれば、それも補助材料として使って構いません。
- 出力は `${TRPG_HOME:-$HOME/.trpg}/reports/` 配下の Markdown ファイルに保存してください。
- cooperative では公開行動中心、`interaction_mode=mixed_interest` では公開行動と private intent を書き分けてください。
- 保存後は、保存先 path と 1〜2 行の要約だけを返してください。
