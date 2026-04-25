#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: prepare-release.sh vX.Y.Z [--no-validate]

Updates release metadata for a release PR:
- cmd/main/main.mbt VERSION
- moon.mod.json version

By default, the script also runs:
- scripts/verify-version.sh
- moon info --target native && moon fmt
- moon check --target native
- moon test cmd/main --target native
- git diff --check
EOF
}

if [ "$#" -eq 0 ]; then
  usage >&2
  exit 2
fi

version_arg=""
run_validation=1

while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-validate)
      run_validation=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [ -n "$version_arg" ]; then
        echo "prepare-release.sh: unexpected argument: $1" >&2
        usage >&2
        exit 2
      fi
      version_arg="$1"
      shift
      ;;
  esac
done

version="${version_arg#v}"
tag="v${version}"

if ! printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "prepare-release.sh: version must be vX.Y.Z or X.Y.Z" >&2
  exit 2
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

if [ -n "$(git status --porcelain)" ]; then
  echo "prepare-release.sh: worktree must be clean before preparing a release" >&2
  exit 1
fi

python3 - "$version" <<'PY'
import json
import re
import sys
from pathlib import Path

version = sys.argv[1]

main_path = Path("cmd/main/main.mbt")
main_text = main_path.read_text(encoding="utf-8")
main_text, replacements = re.subn(
    r'^const VERSION : String = "([^"]*)"$',
    f'const VERSION : String = "{version}"',
    main_text,
    count=1,
    flags=re.MULTILINE,
)
if replacements != 1:
    raise SystemExit("prepare-release.sh: failed to update cmd/main/main.mbt VERSION")
main_path.write_text(main_text, encoding="utf-8")

mod_path = Path("moon.mod.json")
module = json.loads(mod_path.read_text(encoding="utf-8"))
module["version"] = version
mod_path.write_text(json.dumps(module, indent=2) + "\n", encoding="utf-8")
PY

scripts/verify-version.sh "$tag"

if [ "$run_validation" -eq 1 ]; then
  moon info --target native
  moon fmt
  scripts/verify-version.sh "$tag"
  moon check --target native
  moon test cmd/main --target native
  git diff --check
fi

cat <<EOF
Prepared ${tag}.

Next steps:
1. Review the diff.
2. Commit the release metadata update.
3. Open and merge a release PR into main.
4. Tag the merge commit: git tag ${tag} && git push origin ${tag}
EOF
