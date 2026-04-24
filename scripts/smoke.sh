#!/bin/sh
set -eu

TRPG_HOME="${TRPG_HOME:-${HOME}/.trpg}"
export TRPG_HOME

rm -f "$TRPG_HOME/trpg.db"
mkdir -p "$TRPG_HOME/scenarios"

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cp "$repo_dir"/scenarios/*.json "$TRPG_HOME/scenarios/"

trpg --describe >/tmp/trpg-describe.json
trpg --help >/tmp/trpg-help.txt
trpg scenario validate forgotten_library >/tmp/trpg-scenario-validate.json
trpg session init forgotten_library >/tmp/trpg-session.json
if trpg session init forgotten_library >/tmp/trpg-conflict.json 2>/tmp/trpg-conflict.err; then
  echo "smoke: expected session init conflict" >&2
  exit 1
fi
trpg pc templates list >/tmp/trpg-pc-templates.json
trpg pc add alice --template alice >/tmp/trpg-pc-add.json
trpg pc show alice --for-roll tech --tags forced-entry >/tmp/trpg-pc-show.json
trpg roll alice --stat body --scene-default --context "入口の扉を押し開ける" >/tmp/trpg-roll-open.json
trpg status alice add --name 祝福 --source gm --note "次の解錠判定 +1 / scene / consume" --modifier tech:+1 --tags forced-entry,ritual --uses 1 --on-trigger consume >/tmp/trpg-status.json
trpg status alice add --name 動揺 --modifier body:-1 --tags forced-entry,ruins --duration scene >/tmp/trpg-status-scene.json
trpg roll alice --prep --stat tech --tags forced-entry --bonus 12 --grant-to alice --grant tech:+1@forced-entry --grant-name 足場援護 --grant-uses 2 --grant-duration scene --grant-on-trigger consume --context "足場を整える" >/tmp/trpg-roll-prep.json
trpg roll alice --prep --scene-default --stat tech --tags forced-entry --bonus 10 --grant-to alice --grant tech:+1@forced-entry --grant-name 残る援護 --grant-uses 2 --grant-duration scene --grant-on-trigger persist --context "もう一段、支点を整える" >/tmp/trpg-roll-grant-custom.json
trpg pc show alice --for-roll tech --tags forced-entry >/tmp/trpg-pc-show-after-prep.json
trpg roll alice --stat tech --tags forced-entry --target 10 --context "扉の解錠" >/tmp/trpg-roll.json
trpg roll alice --stat mind --target 9 --tags ritual,seal --context "譜面を読み替えて補助線を探る" >/tmp/trpg-roll-alt-target.json
trpg hp alice -3 --context "扉の反動" >/tmp/trpg-hp.json
trpg item give alice "銀の鍵" --desc "封印石棺の鍵" >/tmp/trpg-item-give.json
trpg item transfer alice "司書の亡霊" "短剣" --note "司書へ預けた" >/tmp/trpg-item-transfer.json
trpg log add "扉を開けた" --as alice >/tmp/trpg-log-add.json
trpg log show --kind roll -n 5 >/tmp/trpg-log-show.json
trpg roll history --as alice -n 5 >/tmp/trpg-roll-history.json
trpg scene show >/tmp/trpg-scene-show.json
trpg session goals >/tmp/trpg-session-goals-before.json
trpg prompt player alice --brief --human >/tmp/trpg-prompt-player-before-scene.txt
trpg scene next >/tmp/trpg-scene.json
trpg pc show alice >/tmp/trpg-pc-show-after-scene.json
trpg scene modifier add --name "蔵書の道筋" --next-roll target:-2 --stat tech --tags ancient-text --note "近い棚が見えた" >/tmp/trpg-scene-modifier-add.json
trpg roll alice --scene-default --stat tech --tags ancient-text --context "蔵書の間で搦め手に記録を探る" >/tmp/trpg-roll-scene-default-override.json
roll_event_id="$(sed -n 's/.*\"event_id\":\([0-9][0-9]*\).*/\1/p' /tmp/trpg-roll-scene-default-override.json)"
trpg session note "near miss を軽減して HP 半減" --kind soften --ref-event "$roll_event_id" >/tmp/trpg-session-note-ref.json
trpg contest alice "司書の亡霊" --a-stat tech --b-stat mind --a-tags ancient-text --b-tags ancient-text --context "貸出記録を読み解く" >/tmp/trpg-contest.json
trpg prompt gm --brief >/tmp/trpg-prompt-gm-brief.json
trpg prompt player alice --brief >/tmp/trpg-prompt-player-brief.json
trpg prompt gm >/tmp/trpg-prompt-gm.json
trpg prompt player alice >/tmp/trpg-prompt-player.json
trpg scene next >/tmp/trpg-scene-next.json
trpg scene flag sealed true >/tmp/trpg-flag.json
trpg session goals >/tmp/trpg-session-goals-after.json
trpg session report >/tmp/trpg-session-report.json
trpg session end >/tmp/trpg-session-end.json

if trpg status alice add 失敗例 --tags ritual seal >/tmp/trpg-bad-tags.json 2>/tmp/trpg-bad-tags.err; then
  echo "smoke: expected --tags ritual seal to fail" >&2
  exit 1
fi

if trpg status alice add 失敗例 --modifier tech:+1 >/tmp/trpg-bad-status.json 2>/tmp/trpg-bad-status.err; then
  echo "smoke: expected positional status add name to fail" >&2
  exit 1
fi

if ! grep -q '"target":7' /tmp/trpg-roll-prep.json; then
  echo "smoke: expected --prep to use target 7 at entrance" >&2
  exit 1
fi

if ! grep -q '"uses":2' /tmp/trpg-roll-prep.json || ! grep -q '"duration":"scene"' /tmp/trpg-roll-prep.json; then
  echo "smoke: expected grant options to be reflected in granted_status" >&2
  exit 1
fi

if ! grep -q '"duration":"scene"' /tmp/trpg-roll-grant-custom.json; then
  echo "smoke: expected custom grant duration to be recorded" >&2
  exit 1
fi

if ! grep -q '"uses":2' /tmp/trpg-roll-grant-custom.json; then
  echo "smoke: expected custom grant uses to be recorded" >&2
  exit 1
fi

if ! grep -q '"on_trigger":"persist"' /tmp/trpg-roll-grant-custom.json; then
  echo "smoke: expected custom grant trigger to be recorded" >&2
  exit 1
fi

if ! grep -q '"scene_target_modifier":-2' /tmp/trpg-roll-scene-default-override.json; then
  echo "smoke: expected scene modifier to ease the next matching roll" >&2
  exit 1
fi

if ! grep -q '"kind":"soften"' /tmp/trpg-session-note-ref.json; then
  echo "smoke: expected session note to record note kind" >&2
  exit 1
fi

if grep -q 'applied_at_ms' /tmp/trpg-prompt-player-before-scene.txt; then
  echo "smoke: expected prompt player brief to humanize conditions" >&2
  exit 1
fi

if grep -q '動揺' /tmp/trpg-pc-show-after-scene.json; then
  echo "smoke: expected duration=scene status to expire on scene transition" >&2
  exit 1
fi

echo "smoke ok" >&2
