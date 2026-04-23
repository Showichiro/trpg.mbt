# Showichiro/trpg

Coding Agent TRPG 用の PoC CLI です。Claude Code の Main agent を GM、subagent とユーザをプレイヤーに見立て、判定・HP・状態・ログ・シーン進行を sqlite で決定論的に管理します。

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
trpg session init forgotten_library
trpg scenario show forgotten_library
trpg pc add alice --from ~/.trpg/scenarios/sample_pc_alice.json
trpg pc show alice --for-roll tech
trpg item give alice "銀の鍵" --note "司書の亡霊から受け取った"
trpg roll 2d6+3 --target 10 --as alice --context "扉の解錠"
trpg hp alice -3
trpg status alice add 祝福 --note "次の解錠判定 +1 / 1回消費" --modifier tech:+1 --uses 1 --on-trigger consume
trpg log add "扉を開けた" --as alice
trpg log tail -n 5
trpg session scene librarian --note "蔵書の間へ移動"
trpg session note "司書の亡霊はまだ敵対していない"
trpg prompt gm --human
trpg prompt player alice --human
```

stdout はデフォルトで JSON、stderr は人間向けの短い説明です。`--human` を付けると stdout も人間向けになります。

`trpg prompt gm` と `trpg prompt player` は `logs` と `rolls` を時系列で統合した `直近履歴` を出します。手動ログが少なくても、DB に残った判定履歴から再開しやすくなります。

`trpg scene set <key>` は互換 alias として残していますが、新規運用では `trpg session scene <key> [--note text]` を使ってください。

`trpg pc show <name> --for-roll <body|tech|mind>` は、構造化 status (`--modifier`, `--uses`, `--duration`, `--on-trigger`) の自動合算プレビューを返します。trait やアイテム効果の最終適用判断は引き続き GM が行います。

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

player subagent への handoff には `trpg prompt player <name> --human` を使います。ここには現在シーン、パーティ状態、直近履歴が含まれます。
