#!/bin/sh
set -eu

TRPG_HOME="${TRPG_HOME:-${HOME}/.trpg}"
export TRPG_HOME

rm -f "$TRPG_HOME/trpg.db"
mkdir -p "$TRPG_HOME/scenarios"

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cp "$repo_dir"/scenarios/*.json "$TRPG_HOME/scenarios/"

trpg --describe >/tmp/trpg-describe.json
trpg session init forgotten_library >/tmp/trpg-session.json
if trpg session init forgotten_library >/tmp/trpg-conflict.json 2>/tmp/trpg-conflict.err; then
  echo "smoke: expected session init conflict" >&2
  exit 1
fi
trpg pc add alice --from "$TRPG_HOME/scenarios/sample_pc_alice.json" >/tmp/trpg-pc-add.json
trpg pc show alice >/tmp/trpg-pc-show.json
trpg roll 2d6+3 --target 10 --as alice --context "扉の解錠" >/tmp/trpg-roll.json
trpg hp alice -3 >/tmp/trpg-hp.json
trpg status alice add 毒 --note "ターン終了時 1 ダメ" >/tmp/trpg-status.json
trpg log add "扉を開けた" --as alice >/tmp/trpg-log-add.json
trpg log tail -n 5 >/tmp/trpg-log-tail.json
trpg scene set librarian >/tmp/trpg-scene.json
trpg scene flag met_librarian true >/tmp/trpg-flag.json
trpg prompt gm >/tmp/trpg-prompt-gm.json
trpg prompt player alice >/tmp/trpg-prompt-player.json

echo "smoke ok" >&2
