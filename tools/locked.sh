#!/bin/sh
# Runs one Godot or Blender command at a time across all agents.
# Usage: tools/locked.sh godot --headless --path . --script tests/smoke_test.gd
# If a crash leaves a stale .tool_lock folder behind, delete it.
until mkdir .tool_lock 2>/dev/null; do sleep 3; done
trap 'rmdir .tool_lock' EXIT INT TERM
"$@"
