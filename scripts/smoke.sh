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
trpg status alice add 祝福 --note "次の解錠判定 +1 / scene / consume" --modifier tech:+1 --tags forced-entry,ritual --uses 1 --on-trigger consume >/tmp/trpg-status.json
trpg roll alice --stat tech --tags forced-entry --target 10 --context "扉の解錠" >/tmp/trpg-roll.json
trpg roll alice --stat mind --target 9 --tags ritual,seal --context "譜面を読み替えて補助線を探る" >/tmp/trpg-roll-alt-target.json
trpg hp alice -3 --context "扉の反動" >/tmp/trpg-hp.json
trpg item give alice "銀の鍵" --desc "封印石棺の鍵" >/tmp/trpg-item-give.json
trpg log add "扉を開けた" --as alice >/tmp/trpg-log-add.json
trpg log show --kind roll -n 5 >/tmp/trpg-log-show.json
trpg roll history --as alice -n 5 >/tmp/trpg-roll-history.json
trpg scene show >/tmp/trpg-scene-show.json
trpg session goals >/tmp/trpg-session-goals-before.json
trpg scene next >/tmp/trpg-scene.json
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

echo "smoke ok" >&2
