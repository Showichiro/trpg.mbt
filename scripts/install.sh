#!/bin/sh
set -eu

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
install_dir="${HOME}/.local/bin"
trpg_home="${TRPG_HOME:-${HOME}/.trpg}"

cd "$repo_dir"
moon build --target native

bin_path="$repo_dir/_build/native/debug/build/cmd/main/main.exe"
if [ ! -x "$bin_path" ]; then
  bin_path="$repo_dir/_build/native/debug/build/cmd/main/main"
fi
if [ ! -x "$bin_path" ]; then
  echo "install.sh: built binary was not found" >&2
  exit 1
fi

mkdir -p "$install_dir" "$trpg_home/scenarios" \
  "$HOME/.claude/skills/trpg-gm" "$HOME/.claude/agents" "$HOME/.claude/commands"

cp "$bin_path" "$install_dir/trpg"
chmod 0755 "$install_dir/trpg"
cp "$repo_dir"/scenarios/*.json "$trpg_home/scenarios/"

copy_warn() {
  src="$1"
  dst="$2"
  if [ -e "$dst" ]; then
    echo "install.sh: overwrite ${dst}" >&2
  fi
  cp "$src" "$dst"
}

copy_warn "$repo_dir/.claude/skills/trpg-gm/SKILL.md" "$HOME/.claude/skills/trpg-gm/SKILL.md"
copy_warn "$repo_dir/.claude/agents/trpg-player.md" "$HOME/.claude/agents/trpg-player.md"
copy_warn "$repo_dir/.claude/commands/trpg-start.md" "$HOME/.claude/commands/trpg-start.md"

echo "installed trpg at ${install_dir}/trpg" >&2
echo "installed scenarios at ${trpg_home}/scenarios" >&2
