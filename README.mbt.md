# Showichiro/trpg

Coding Agent TRPG 用の PoC CLI です。Claude Code の Main agent を GM、subagent とユーザをプレイヤーに見立て、判定・HP・状態・アイテム・シーン進行を sqlite で決定論的に管理します。

## セットアップ

```bash
moon check
moon test
bash scripts/install.sh
```

インストール先:

- `~/.local/bin/trpg`
- `~/.trpg/scenarios/*.json`
- `~/.claude/skills/trpg-gm/SKILL.md`
- `~/.claude/agents/trpg-player.md`
- `~/.claude/commands/trpg-start.md`

`TRPG_HOME` を指定すると DB とシナリオ配置先を変更できます。

## 基本コマンド

```bash
trpg --describe
trpg --help
trpg session init forgotten_library
trpg session show
trpg session goals
trpg scenario show forgotten_library
trpg pc templates list
trpg pc add alice --template alice
trpg pc show alice --for-roll tech --tags forced-entry
trpg scene show
trpg roll alice --stat tech --scene-default --tags forced-entry --context "重い扉の解錠"
trpg roll orion --stat mind --target 9 --tags ritual,seal --context "封印の手順を譜面に落とし込む"
trpg status alice add --name 祝福 --note "次の解錠判定 +1 / scene / consume" --modifier tech:+1 --tags forced-entry,ritual --uses 1 --on-trigger consume
trpg item give alice "銀の鍵" --desc "封印石棺の鍵"
trpg contest alice "司書の亡霊" --a-stat tech --b-stat mind --context "鍵の所在を探る"
trpg attack "司書の亡霊" alice --atk mind --def tech --damage 1d6 --context "怨念の奔流"
trpg hp alice -3 --context "怨念の余波"
trpg log add "扉を開けた" --as alice
trpg log show --kind roll -n 5
trpg roll history --as alice -n 5
trpg scene next --note "蔵書の間へ移動"
trpg session note "司書の亡霊はまだ敵対していない"
trpg prompt gm --brief --human
trpg prompt player alice --brief --human
trpg session report
trpg session end
```

stdout はデフォルトで JSON、stderr は人間向けの短い説明です。`--human` を付けると stdout も人間向けになります。

`trpg roll <name> --stat ...` は PC/NPC の能力値、trait、inventory item、structured status を自動合算します。`base_stat` も加算対象です。`--scene-default` を付けると現在シーンの `difficulty` を既定値として使い、`--stat` 併用時は target/tags を scene から流用したまま stat だけ差し替えます。

trait / item / status の auto-apply は `effect.stat == --stat` かつ tag 一致が条件です。tag が一致していても stat が違えば乗りません。そういう候補は `skipped_sources` に理由付きで出ます。

scene default を使う搦め手・準備・援護判定では `trpg roll orion --scene-default --stat tech --tags ritual,seal ...` のように stat だけ差し替える形を優先してください。scene target 自体を変えたいときだけ `--target N` を明示します。

`--tags` は comma-separated です。複数タグは `--tags ritual,seal` のように 1 引数で渡してください。`--tags ritual seal` は usage error になります。

準備判定や援護判定の成功は、原則 `trpg status ... add --name ... --uses 1 --on-trigger consume` の一時 status として次の本命ロールへつなぎます。本命ロールの stat に合わせた `--modifier <stat>:+N` を使ってください。

`trpg prompt gm` と `trpg prompt player` は `events` を正本とした `直近履歴` を出します。scene 遷移、item 変化、HP、status、roll、contest、attack が時系列でまとまるので、手動ログが少なくても再開しやすくなります。`--brief` を付けると handoff 向けの軽量版になります。

`trpg session goals` は現在の goal 達成状況を軽量に確認します。`scene_flag(...)` 条件を持つ goal を運用するときは、`trpg scene flag` とセットで使ってください。flag 更新後は `trpg prompt gm --human` を取り直すと文脈が揃います。

`trpg scene set <key>` は互換 alias として残していますが、新規運用では `trpg scene list|show|next` と `trpg session scene <key> [--note text]` を使ってください。

`trpg pc show <name> --for-roll <body|tech|mind> --tags ...` は、実際の `roll` と同じ自動合算プレビューを返します。

終了コード:

- `0`: 成功
- `1`: 一般エラー
- `2`: 使用法エラー
- `3`: リソース未検出
- `4`: 権限エラー
- `5`: コンフリクト

## 検証

```bash
bash scripts/install.sh
cd /tmp
bash ~/ghq/github.com/Showichiro/trpg.mbt/scripts/smoke.sh
```

Claude Code では `/trpg-start` を実行すると GM skill が起動します。

fresh start では、GM skill は開始前に参加人数と参加 PC を確認します。`forgotten_library` の既定候補は 1 人なら `alice`、2 人なら `alice` と `orion` です。

player subagent への handoff には `trpg prompt player <name> --human --brief` を使います。ここには現在シーン、パーティ状態、直近履歴が含まれます。シーン遷移直後、援護ターン、分岐判断では GM が選択肢を補足して構いません。
