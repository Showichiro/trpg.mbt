---
name: trpg-retrospective
description: TRPG セッションの振り返りレポートを Markdown の読み物として保存する。ユーザが「セッションを振り返りたい」「プレイログを読み物にして」「after action report を出して」などと言ったときに使う。
---

# TRPG Retrospective Skill

この skill は、最新または active session を材料にして、**読み物として通る Markdown レポート** を `TRPG_HOME/reports/` へ保存する。

正本は `events` と session/scenario/character の構造化情報で、同じ会話内に残っている GM narration や subagent の private intent は副材料として使ってよい。CLI と矛盾したら CLI を優先する。

## 使うもの

1. `scripts/export_session_context.py`
   - active session があればそれを、無ければ latest session を自動選択する
   - session / scenario / characters / events / 保存先候補を JSON で返す
2. `trpg session report --human`
   - 人間向けの短い要約を補助的に見る
3. 現在の会話
   - 同じセッション中に GM が出した描写
   - `public_handoff_text` / `private_handoff_text`
   - subagent の `## 非公開意図`

## ワークフロー

1. まず context を取る。

```bash
python3 .claude/skills/trpg-retrospective/scripts/export_session_context.py
```

- 特定 session を読みたいときだけ `--session-id <id>` を付ける
- active/latest が無ければここで止める

2. 補助要約を取る。

```bash
trpg session report --human
```

3. 同じ会話内に、今回のセッションの narration や subagent 応答が残っていれば読む。

- cooperative では、公開 narration を本編の肉付けに使う
- `mixed_interest` では、`private_handoff_text` や subagent の `## 非公開意図` が残っていれば「裏側の流れ」に使ってよい
- private 情報が会話に無ければ、**推測で補わない**

4. Markdown を作る。標準構成は次で固定する。

```md
# {title}

- scenario: ...
- session: ...
- outcome: ...
- generated_at: ...

## 導入

## 本編

## 転換点

## 裏側の流れ

## 主要判定

## 終幕

## 付録
```

5. 出力先は script が返す `report_path_suggestion` を使う。既定は:

```text
${TRPG_HOME}/reports/<scenario_id>-<session_id>.md
```

同名があるときは timestamp suffix 付き候補が返る。`reports/` が無ければ作ってよい。

## 書き方

- JSON の再掲ではなく、**通読できる prose** にする
- ただし事実から外れない。判定結果、scene 遷移、HP 変動、item 移動は `events` に合わせる
- 本編は scene ごとに流れをつなぎ、印象的な判定だけを選ぶ
- `session report --human` の文面は引用せず、再構成して書く

### cooperative

- 公開された行動と卓上 narration を自然につなぐ
- 裏側は「判断の流れ」「支援の噛み合い」「失敗の連鎖からどう戻したか」などを書く

### mixed_interest

- `## 裏側の流れ` では、公開行動と private intent を明確に書き分ける
- 卓上で見えていたことと、裏で何を狙っていたかを混ぜない
- `private_handoff_text` や subagent の `## 非公開意図` が無いなら、そのパートは薄くしてよい

## 最低限入れる内容

- 参加 PC/NPC と最終 outcome
- 主要 goal の達成/未達
- 印象的だった 3〜8 個の event
- 重要な判定の成否と転換点
- mixed-interest なら、どこで利害がずれ、どう破綻せずに進んだか

## 返答

レポート保存後の返答は短くてよい。

- 保存先 path
- 対象 session
- 1〜2 行の要約

## 注意

- active/latest の自動選択があるので、ユーザが明示していない限り session id を聞き返さない
- private intent は「振り返り」用途なので含めてよいが、会話に残っていないものは作らない
- `interaction_mode=mixed_interest` でも、後付けの邪推で対立を誇張しない
