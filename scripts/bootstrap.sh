#!/usr/bin/env bash
# Brings a fresh checkout of MDViewer.Mobile to a runnable state:
#   1. Initializes/updates the vendor/markdownviewer submodule (pinned commit,
#      see vendor/markdownviewer's checked-out ref — not the v0.7.0 tag; see
#      README.md's "Why the submodule is pinned to a commit, not the tag").
#   2. Fetches the release-published, checksum-verified mobile binaries via
#      the plugin's own fetch script.
#
# Idempotent — safe to re-run; the submodule update is a no-op once checked
# out, and fetch_binaries.sh skips re-downloading via its own marker file.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

echo "==> Initializing vendor/markdownviewer submodule..."
if ! git submodule update --init --recursive vendor/markdownviewer; then
  echo "error: failed to init/update the vendor/markdownviewer submodule." >&2
  echo "       Check network access to https://github.com/sriannamalai/markdownviewer.git" >&2
  echo "       and that this checkout has a .gitmodules entry for vendor/markdownviewer." >&2
  exit 1
fi

plugin_dir="$repo_root/vendor/markdownviewer/flutter/mdviewer"
fetch_script="$plugin_dir/tool/fetch_binaries.sh"

if [[ ! -x "$fetch_script" ]]; then
  echo "error: $fetch_script not found or not executable." >&2
  echo "       The submodule may be checked out at an unexpected ref — expected the" >&2
  echo "       flutter/mdviewer plugin layout to exist under vendor/markdownviewer." >&2
  exit 1
fi

echo "==> Fetching released mobile binaries (mdviewer v0.7.0, checksum-verified)..."
if ! MDVIEWER_VERSION="v0.7.0" "$fetch_script"; then
  echo "error: fetch_binaries.sh failed — see output above." >&2
  echo "       Common causes: no network access to github.com release assets," >&2
  echo "       or tool/checksums.txt in the pinned submodule commit lacking a" >&2
  echo "       v0.7.0 entry. See README.md for which commit is pinned and why." >&2
  exit 1
fi

echo "==> Bootstrap complete."
