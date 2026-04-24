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
- `~/.claude/skills/trpg-gm/`
- `~/.claude/skills/trpg-retrospective/`
- `~/.claude/agents/trpg-player.md`
- `~/.claude/commands/trpg-start.md`
- `~/.claude/commands/trpg-retrospective.md`

`TRPG_HOME` を指定すると DB とシナリオ配置先を変更できます。

`scripts/install.sh` は開発者向け bootstrap です。一般利用者は repo を clone していなくても、配布済み `trpg` バイナリから `trpg scenario bundled` / `trpg scenario install <scenario_id>` で同梱 scenario を導入できます。

この CLI は **非対話がデフォルト** です。ユーザ本人が叩いてもよいですし、AI エージェントが `scenario bundled/install/list/show` や `scenario import` と `session init` を順に実行する前提でも使えます。

## 基本コマンド

```bash
trpg --describe
trpg --help
trpg scenario list
trpg scenario bundled
trpg scenario install forgotten_library
trpg scenario import https://example.com/scenarios/forgotten_library.json
trpg scenario import /path/to/local_scenario.json
trpg session init forgotten_library
trpg session show
trpg session goals
trpg scenario show forgotten_library
trpg pc templates list
trpg pc add alice --template alice
trpg pc show alice --for-roll tech --tags forced-entry
trpg scene show
trpg roll alice --preview --scene-default --stat tech --tags forced-entry --skip-status "祝福"
trpg roll alice --stat tech --scene-default --tags forced-entry --context "重い扉の解錠"
trpg roll orion --prep --scene-default --stat mind --grant-to alice --grant tech:+1@ritual,seal --grant-name 譜面援護 --grant-uses 2 --grant-duration scene --grant-on-trigger consume --context "封印の手順を譜面に落とし込む"
trpg status alice add --name 祝福 --source orion --note "次の解錠判定 +1 / scene / consume" --modifier tech:+1 --tags forced-entry,ritual --uses 1 --on-trigger consume
trpg scene progress entrance-door +1 --note "蝶番が少し緩んだ"
trpg scene modifier add --name "扉が緩む" --next-roll target:-2 --stat tech --tags forced-entry --note "次の解錠を少し易しくする"
trpg item give alice "銀の鍵" --desc "封印石棺の鍵"
trpg item transfer alice orion "銀の鍵" --add-tags ritual,seal --set-effect mind:+1 --note "封印役へ渡す"
trpg contest alice "司書の亡霊" --a-stat tech --b-stat mind --context "鍵の所在を探る"
trpg attack "司書の亡霊" alice --atk mind --def tech --damage 1d6 --context "怨念の奔流"
trpg hp alice -3 --context "怨念の余波"
trpg log add "扉を開けた" --as alice
trpg log show --kind roll -n 5
trpg roll history --as alice -n 5
trpg scene next --note "蔵書の間へ移動"
trpg session note "司書の亡霊はまだ敵対していない"
trpg session note "near miss を軽減して HP 半減" --kind soften --ref-event 37
trpg prompt gm --brief --human
trpg prompt player alice --brief --human
trpg session report
trpg session end
```

stdout はデフォルトで JSON、stderr は人間向けの短い説明です。`--human` を付けると stdout も人間向けになります。

一般利用者向けの正導線は次です。

```bash
trpg scenario bundled
trpg scenario install forgotten_library
trpg scenario list
trpg session init forgotten_library
```

`trpg scenario bundled` は CLI に同梱された導入可能 scenario を一覧表示します。`trpg scenario install <scenario_id>` はその中から 1 本を `TRPG_HOME/scenarios/<scenario_id>.json` に展開します。既に同じ id がある場合は conflict になり、`--force` を付けたときだけ置き換えます。active session がその scenario を使っている間は replace/remove できません。

`trpg scenario import <url-or-path>` は URL とローカル path の両方を受け付けます。外部配布 scenario を導入したいときはこちらを使ってください。取り込み先は `TRPG_HOME/scenarios/<scenario_id>.json` です。既に同じ id がある場合は conflict になり、`--force` を付けたときだけ置き換えます。active session がその scenario を使っている間は replace/remove できません。

`trpg scenario list` は install/import 済み scenario だけを JSON で返します。各 entry には `id`, `title`, `summary`, `path`, `origin`, `source_url`, `installed_at_ms` が入り、AI エージェントが候補選定や導入判定にそのまま使えます。bundled 候補は `trpg scenario bundled` を見てください。

同梱 scenario は現状 3 本です。

- `forgotten_library`: 1〜2 人向けの封印回収シナリオ
- `festival_bathhouse_fire`: 2〜3 人向けの災害対応シナリオ
- `midnight_auction`: 3〜4 人向けの利害対立つき競売シナリオ

同梱 sample PC は `alice`, `orion`, `bram`, `mina` の 4 人です。

`trpg scenario install <scenario_id>` は、その scenario が `party_setup.sample_pcs` に列挙している bundled sample PC も一緒に `TRPG_HOME/scenarios/` へ展開します。`trpg pc add --template alice` のような template 追加は repo checkout なしで動きます。

`trpg roll <name> --stat ...` は PC/NPC の能力値、trait、inventory item、structured status を自動合算します。`base_stat` も加算対象です。`--scene-default` を付けると現在シーンの `difficulty` を既定値として使い、scene tags と `--tags` は **union** されます。override ではありません。`--stat` 併用時は target/tags を scene から流用したまま stat だけ差し替えます。`--prep` は準備・援護向けの sugar で、target 未指定時に現在 scene の target を 2 下げ、scene target が無ければ 9 を使います。

trait / item / status の auto-apply は `effect.stat == --stat` かつ tag 一致が条件です。tag が一致していても stat が違えば乗りません。そういう候補は `skipped_sources` に理由付きで出ます。custom tag を足すと既存 trait/item/status の tag 一致が外れて auto-apply が減ることがあるので、まずは既存 scene tag に丸め、auto-apply を意図的に変えたいときだけ新規 tag を足す方が安全です。

scene default を使う搦め手では `trpg roll orion --scene-default --stat tech --tags ritual,seal ...` のように stat だけ差し替える形を優先してください。準備・援護は `trpg roll orion --prep --scene-default --stat mind ...` のように `--prep` と `--scene-default` を併用して構いません。このとき target は `--prep` 側が決め、scene tags は `--scene-default` 側からも流用されます。scene target 自体を変えたいときだけ `--target N` を明示します。

actor-aware の実ロールでは、`--target N` / `--scene-default` / `--prep` のいずれかで target を必ず解決してください。どれも付けずに振るのは usage error です。target 未解決の stack 確認だけしたいときは `--preview` を使います。

`--tags` は comma-separated です。複数タグは `--tags ritual,seal` のように 1 引数で渡してください。`--tags ritual seal` は usage error になります。

準備判定や援護判定の成功は、原則 `trpg roll ... --grant-to <target> --grant tech:+1@ritual,seal` で一時 status を自動付与します。`--grant-name`、`--grant-uses N`、`--grant-duration scene|infinite`、`--grant-on-trigger consume|persist` で挙動を明示指定できます。デフォルトは `uses=1 / on_trigger=consume / duration 指定なし` で、consume されるまで scene を跨いで残ります。今の実装では `duration 指定なし` と `duration=infinite` は同じ挙動です。`--grant-to` に自分自身を指定して self-grant しても構いません。自動 grant は `HIT` 時だけ発動します。near miss で部分付与したいときは、手動で `trpg status ... add --name ... --source 援護者 --uses 1 --on-trigger consume` を使い、本命ロールの stat に合わせた `--modifier <stat>:+N` を amount 半減・最低 1 に丸めて積んでください。

ロール前に stack だけ見たいときは `trpg roll <name> --preview ...` を使います。これは実ロールと同じ解決経路で `sources / skipped_sources / target / scene modifier / grant_plan` を返しますが、ダイスは振らず、status 消費や grant も発生させません。`target 11` の本命、複数 grant や scene modifier が重なる判定、off-stat 判定では preview を推奨します。`--skip-status "状態名"` を付けると、そのロールだけ auto-apply を外して温存できます。

`margin=0` は純粋な HIT として扱います。機械的不利は付けず、必要なら描写上の緊張感だけ残してください。`margin>=3` は `special=crit` ではありませんが、副次好機 1 つを検討してよい目安です。`special=crit` は「難度 1 段階軽減相当」「`+2〜+3 / uses=1` の援護 status」「副次好機 1 つ」のいずれかを目安に扱うと安定します。`special=fumble` は一段重く扱います。

`trpg prompt gm` と `trpg prompt player` は `events` を正本とした `直近履歴` を出します。scene 遷移、item 変化、HP、status、roll、contest、attack が時系列でまとまるので、手動ログが少なくても再開しやすくなります。`--brief` を付けると handoff 向けの軽量版になります。

`trpg prompt player <name>` を初めて呼ぶと、その PC が subagent 運用対象とみなされ、session 内に play style がランダム割当されます。style は提案傾向にだけ効き、数値補正ではありません。同じ PC をその session 中に何度 handoff しても同じ style が使われます。さらに、subagent には毎ターン hidden な `quality` と `immersion` の runtime tuning が与えられ、時々かなり筋の良い手、時々かなり雑で妙な手、時々解決より対話や観察を優先する手が混ざります。確認や調整には `trpg pc style show <name>`、再抽選には `trpg pc style reroll <name>`、明示指定には `trpg pc style set <name> <style_id>` を使ってください。scenario に `interaction_mode: mixed_interest` がある場合は、subagent の秘密意図を卓上に出さない半協力モードとして扱います。

`trpg session goals` は現在の goal 達成状況を軽量に確認します。`scene_flag(...)` 条件を持つ goal を運用するときは、`trpg scene flag` とセットで使ってください。`trpg scene flag` は current scene にしか書き込まず、goal 判定も指定 scene の flags だけを見ます。違う scene で立てた flag はその goal には効きません。`inventory_ever_contained(...)` は「一度でも保持した」を sticky に評価する goal です。flag 更新後は `trpg prompt gm --human` を取り直すと文脈が揃います。

`trpg scene set <key>` は互換 alias として残していますが、新規運用では `trpg scene list|show|next` と `trpg session scene <key> [--note text]` を使ってください。

段階的チャレンジや repeated near miss は `trpg scene progress <key> <delta> [--note text]` で積み上げられます。`scene flag` は bool/string の節目、`scene progress` は段階的な蓄積向けです。同じ障害で 2 連続 near miss なら `scene progress` を 1 残し、3 連続なら `trpg scene modifier add --name ... --next-roll target:-2 ...` で次判定を 1 段階易化する運用に寄せるとぶれません。

NPC との競合は、対話や説得なら通常 `roll`、組みつき・押さえ込み・縄で絡めるなら `trpg contest`、呪詞や怨念の奔流のように直接ダメージが出るなら `trpg attack` を優先すると整理しやすいです。例:

```bash
trpg contest alice "司書の亡霊" --a-stat body --b-stat body --context "組みついて動きを止める"
trpg attack "司書の亡霊" alice --atk mind --def tech --damage 1d6 --context "怨念の奔流"
```

near miss や fumble の軽減裁定は、`trpg session note "HP 半減適用" --kind soften --ref-event 37` のように対応 event に紐づけて残せます。後から `session report` や `log show` を見返すときに追跡しやすくなります。

`duration=scene` の status は scene 遷移時に自動で消えます。シーン跨ぎで残したい効果だけ別 duration を使ってください。アイテム操作は「新規取得 = give」「受け渡し = transfer」「消耗・破棄 = drop」で分けると迷いません。NPC の初期 inventory を PC へ渡す定番フローも `trpg item transfer 司書の亡霊 orion 銀の鍵` の一発で済みます。

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

`/trpg-retrospective` を実行すると、最新または active session を対象にした振り返り読み物を `${TRPG_HOME:-$HOME/.trpg}/reports/` へ保存できます。skill は `.claude/skills/trpg-retrospective/scripts/export_session_context.py` で session / scenario / characters / events を集め、同じ会話に残っている narration や private intent があれば補助的に使います。

fresh start では、GM skill は開始前に参加人数と参加 PC を確認します。参加候補は選んだ scenario の `party_setup.default_participants` を正とし、`party_setup` が無ければ `recommended_party_size.min` を見て、それも無ければ確認に戻ります。scenario 定義の NPC は `session init` 時に自動登録されるので、GM が追加 NPC を足したいときだけ手動登録します。

開幕描写では、雰囲気説明の直後に短い卓内ガイドを入れる運用を推奨します。最低限、`body / tech / mind` の意味、各 PC の得意分野、準備 / 援護を挟めることだけを 3〜5 行で案内すると、初見でも scene の読み方が分かりやすくなります。

player subagent への handoff には `trpg prompt player <name> --brief` の JSON に含まれる `private_handoff_text` を使います。`handoff_text` は互換 alias です。`text` や `trpg prompt player <name> --human --brief` は GM inspection 用で、hidden runtime tuning は含みません。`private_handoff_text` には現在シーン、パーティ状態、直近履歴、active status、play style に加えて、そのターン限りの quality / immersion の hidden tuning が入ります。`interaction_mode=mixed_interest` の scenario では、JSON に `public_handoff_text` も含まれ、公開情報だけの prompt を別に持てます。運用モード指定があればそれに従ってください。シーン遷移直後、援護ターン、分岐判断では末尾に次のような `## GM補足` セクションを足すと安定します。

```text
## GM補足
- 候補A: ...
- 候補B: ...
- 候補C: ...
```

subagent の返答をそのまま機械要約せず、GM はまず卓上で起きたこととして再表現します。意図、しぐさ、短い台詞、場の変化を 1〜3 段落で描写し、その後に必要なら `判定: ...` を 1 行だけ添える形が安定します。候補提示も同様で、scene id や tag、grant/status 名、`判定回避` のような内部語は見せず、世界内の選択肢として書く方が体験が自然です。`interaction_mode=mixed_interest` の scenario では、GM が卓上に戻してよいのは `公開行動` だけで、秘密の狙い、温存したい交渉材料、誰を出し抜きたいかは流さないでください。
