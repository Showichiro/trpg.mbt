#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: verify-version.sh [vX.Y.Z|X.Y.Z]

Verifies that cmd/main/main.mbt and moon.mod.json agree on the same release
version. When an expected version is provided, it must match the repository
metadata.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "$#" -gt 1 ]; then
  echo "verify-version.sh: too many arguments" >&2
  usage >&2
  exit 2
fi

expected_version="${1:-}"
expected_version="${expected_version#v}"

if [ -n "$expected_version" ] &&
  ! printf '%s' "$expected_version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "verify-version.sh: expected version must be vX.Y.Z or X.Y.Z" >&2
  exit 2
fi

cli_source_version="$(
  sed -n 's/^const VERSION : String = "\(.*\)"$/\1/p' cmd/main/main.mbt
)"
module_version="$(
  python3 - <<'PY'
import json

with open("moon.mod.json", encoding="utf-8") as fp:
    print(json.load(fp)["version"])
PY
)"

if [ -z "$cli_source_version" ]; then
  echo "verify-version.sh: cmd/main/main.mbt VERSION was not found" >&2
  exit 1
fi

if [ "$cli_source_version" != "$module_version" ]; then
  echo "verify-version.sh: cmd/main/main.mbt VERSION is ${cli_source_version}, moon.mod.json version is ${module_version}" >&2
  exit 1
fi

if [ -n "$expected_version" ] && [ "$cli_source_version" != "$expected_version" ]; then
  echo "verify-version.sh: repository version is ${cli_source_version}, expected ${expected_version}" >&2
  exit 1
fi

echo "version metadata ok: ${cli_source_version}"
