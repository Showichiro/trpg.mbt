---
description: Coding Agent TRPG を開始する
---

TRPG GM skill を使って `forgotten_library` を扱ってください。

- active session がある場合は、そのまま再開してください。
- active session が無い場合は、**最初に参加人数と参加 PC を確認してください**。
- 参加人数または参加 PC が未確定のまま `trpg session init forgotten_library --if-not-exists` / `trpg pc add` / `trpg prompt gm --human` を実行してゲームを始めないでください。
- fresh start で人数だけ指定された場合は、1 人なら `alice`、2 人なら `alice` と `orion` を既定候補として提案してください。
- fresh start では `trpg scenario show forgotten_library` を確認し、goal に `scene_flag(...)` がある場合は対応シーンで `trpg scene flag` を使ってください。
- 判定は原則 `trpg roll <name> --scene-default --stat ... --tags ...` を使ってください。準備・援護は `trpg roll <name> --prep ...` を優先し、scene target 自体を変えるときだけ `--target N` を明示してください。
- trait / item / status の auto-apply は `effect.stat == --stat` が必須です。tag 一致だけでは乗らないので、必要なら `skipped_sources` を確認してください。
- 準備・援護の成功は、原則 `trpg roll ... --grant-to <target> --grant tech:+1@ritual,seal` のように一時 status を自動付与してください。手動で積むなら `trpg status ... add --name ... --source 援護者 --modifier ... --tags ritual,seal --uses 1 --on-trigger consume` を使い、本命ロールの stat に合わせてください。
- シーン遷移では `trpg scene list|show|next` と `trpg session scene <id>` を使ってください。
- 途中の goal 確認には `trpg session goals` を使ってください。
- `scene flag` を更新した直後も `trpg prompt gm --human` の再取得対象です。
- `special=crit` は難度 1 段階軽減相当、または `+2〜+3 / uses=1` の援護 status、または副次好機 1 つを目安に扱ってください。
- 終幕では `trpg session report` を確認し、必要なら `trpg session end` を実行してください。
- player handoff では `trpg prompt player <name> --human --brief` を主情報源にしてください。必要なら GM が見えている状況や選択肢を補足して構いません。
- ユーザが即開始を明示した場合は、`party_setup.default_participants` を使ってそのまま開始して構いません。
