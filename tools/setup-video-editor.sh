#!/usr/bin/env bash
# Clone the video editor skill pack next to this repo and link its skills into
# .claude/skills/. Safe to rerun: it keeps an existing clone, .env,
# MASTER_CONTEXT.md and existing skill links.
# Usage: bash tools/setup-video-editor.sh [--demo]
set -euo pipefail
REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PACK_DIR="${VIDEO_EDITOR_PACK_DIR:-$REPO_DIR/../mrpaidsocial/mrpaidsocial-video-editor-agent}"
PACK_URL="https://github.com/mrpaidsocial/mrpaidsocial-video-editor-agent"

if [ ! -d "$PACK_DIR/.git" ]; then
  mkdir -p "$(dirname -- "$PACK_DIR")"
  GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 "$PACK_URL" "$PACK_DIR"
fi

if [ "${1:-}" = "--demo" ]; then
  bash "$PACK_DIR/scripts/setup.sh" --demo
fi
bash "$PACK_DIR/scripts/setup.sh" --no-install --link-skills "$REPO_DIR"
