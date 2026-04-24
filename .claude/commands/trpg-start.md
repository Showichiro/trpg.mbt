---
description: Coding Agent TRPG を開始する
---

TRPG GM skill を使って `forgotten_library` を扱ってください。

- active session がある場合は、そのまま再開してください。
- active session が無い場合は、**最初に参加人数と参加 PC を確認してください**。
- 参加人数または参加 PC が未確定のまま `trpg session init forgotten_library --if-not-exists` / `trpg pc add` / `trpg prompt gm --human` を実行してゲームを始めないでください。
- fresh start で人数だけ指定された場合は、1 人なら `alice`、2 人なら `alice` と `orion` を既定候補として提案してください。
- fresh start では `trpg scenario show forgotten_library` を確認し、goal に `scene_flag(...)` がある場合は対応シーンで `trpg scene flag` を使ってください。
- 判定は原則 `trpg roll <name> --stat ... --scene-default --tags ...` を使ってください。
- シーン遷移では `trpg scene list|show|next` と `trpg session scene <id>` を使ってください。
- 途中の goal 確認には `trpg session goals` を使ってください。
- 終幕では `trpg session report` を確認し、必要なら `trpg session end` を実行してください。
- player handoff では `trpg prompt player <name> --human --brief` を主情報源にしてください。必要なら GM が 1〜2 文だけ見えている状況を補足して構いません。
