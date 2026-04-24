---
description: Coding Agent TRPG を開始する
---

TRPG GM skill を使って TRPG を開始してください。

- ユーザが scenario id を指定したらそれを使ってください。
- ユーザが scenario の URL またはローカル path を渡したら、先に `trpg scenario import <url-or-path>` を実行してください。
- scenario が未指定なら `trpg scenario list` を確認し、候補が 1 件だけならそれを使い、複数あるならユーザに確認してください。
- 特に指定が無いときだけ `forgotten_library` を既定シナリオとして扱って構いません。

- active session がある場合は、そのまま再開してください。
- active session が無い場合は、**最初に参加人数と参加 PC を確認してください**。
- 参加人数または参加 PC が未確定のまま `trpg session init forgotten_library --if-not-exists` / `trpg pc add` / `trpg prompt gm --human` を実行してゲームを始めないでください。
- fresh start で人数だけ指定された場合は、1 人なら `alice`、2 人なら `alice` と `orion` を既定候補として提案してください。
- fresh start では `trpg scenario show forgotten_library` を確認し、goal に `scene_flag(...)` がある場合は対応シーンで `trpg scene flag` を使ってください。
- opening では、雰囲気描写の直後に `body / tech / mind` の意味、各 PC の得意分野、準備 / 援護を挟めることだけを 3〜5 行で案内してください。
- 判定は原則 `trpg roll <name> --scene-default --stat ... --tags ...` を使ってください。`--scene-default` と `--tags` は union され、override ではありません。準備・援護は `trpg roll <name> --prep ...` を優先してください。`--prep` は target 未指定時に現在 scene の target を 2 下げ、scene target が無いときは 9 を使います。`--prep --scene-default` は併用可で、target は prep、scene tags は scene-default 由来も使います。scene target 自体を変えるときだけ `--target N` を明示してください。
- trait / item / status の auto-apply は `effect.stat == --stat` が必須です。tag 一致だけでは乗らないので、必要なら `skipped_sources` を確認してください。
- custom tag を足すと既存 trait/item/status の tag 一致が外れて auto-apply が減ることがあります。まず既存 scene tag に丸め、auto-apply を意図的に変えたいときだけ新規 tag を足してください。
- 準備・援護の成功は、原則 `trpg roll ... --grant-to <target> --grant tech:+1@ritual,seal` のように一時 status を自動付与してください。`--grant-name`、`--grant-uses`、`--grant-duration`、`--grant-on-trigger` は既存機能です。デフォルトは `uses=1 / on_trigger=consume / duration 指定なし` で、consume されるまで scene を跨いで残ります。今の実装では `duration 指定なし` と `duration=infinite` は同じです。self-grant しても構いません。手動で積むなら `trpg status ... add --name ... --source 援護者 --modifier ... --tags ritual,seal --uses 1 --on-trigger consume` を使い、本命ロールの stat に合わせてください。
- ロール前に何が乗るかだけ確認したいときは `trpg roll <name> --preview ...` を使ってください。必要なら `--skip-status "状態名"` でそのロールだけ auto-apply を外せます。
- シーン遷移では `trpg scene list|show|next` と `trpg session scene <id>` を使ってください。
- 途中の goal 確認には `trpg session goals` を使ってください。
- `scene flag` を更新した直後も `trpg prompt gm --human` の再取得対象です。
- 同じ障害で 2 連続 near miss なら `trpg scene progress <key> <delta>` を残してください。3 連続なら `trpg scene modifier add --name "扉が緩む" --next-roll target:-2 --stat tech --tags forced-entry` のように次判定を 1 段階易化して構いません。
- near miss / fumble の軽減裁定は `trpg session note "HP 半減適用" --kind soften --ref-event <event_id>` のように残してください。
- `duration=scene` の status は scene 遷移時に自動で消えます。
- アイテムの新規取得は `item give`、受け渡しは `item transfer`、消耗・破棄は `item drop` を使ってください。受け渡し時にタグや効果を付け直すなら `trpg item transfer <from> <to> <item> --add-tags ritual,seal --set-effect mind:+1` を使います。
- `special=crit` は難度 1 段階軽減相当、または `+2〜+3 / uses=1` の援護 status、または副次好機 1 つを目安に扱ってください。
- `margin=0` は純粋な HIT です。機械的不利は付けず、必要なら描写上の緊張感だけ残してください。
- `margin>=3` は `special=crit` ではありませんが、副次好機 1 つを検討して構いません。
- 終幕では `trpg session report` を確認し、必要なら `trpg session end` を実行してください。
- player handoff では `trpg prompt player <name> --brief` の JSON に含まれる `handoff_text` を主情報源にしてください。`text` や `--human --brief` は GM inspection 用です。初回呼び出し時は、その PC に subagent 用 play_style がランダム割当され、session 中は永続化されます。加えて、subagent には毎ターン hidden な quality / immersion の runtime tuning が与えられます。必要なら末尾に `## GM補足` セクションを足し、箇条書きで選択肢候補を書いて構いません。
- subagent の返答を戻すときは、まず卓上で起きたこととして再表現し、その後に必要なら `判定: ...` を 1 行だけ添えてください。候補提示は世界内の選択肢として書き、scene id や tag、grant/status 名、`判定回避` のような内部語は見せないでください。
- scenario 定義の NPC は `session init` で自動登録されます。追加 NPC が必要なときだけ手動で登録してください。
- ユーザが即開始を明示した場合は、`party_setup.default_participants` を使ってそのまま開始して構いません。運用モード指定があればそれにも従ってください。失敗時に即 bad end / irreversible loss / goal lockout を起こしうる判定だけは一度確認してください。
