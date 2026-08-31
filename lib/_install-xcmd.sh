#!/usr/bin/env bash
# x-cmd-action/ai — shared installer for x-cmd.
# Used by all subcommand action.yml files.

set -euo errexit

# Source x-cmd into current shell.
if [ -f "$HOME/.x-cmd.root/X" ]; then
  ___x_cmd_CLAUDECODE_READY=1 . "$HOME/.x-cmd.root/X"
else
  echo "Installing x-cmd..."
  bash -c "$(curl -fsSL https://get.x-cmd.com)" 2>&1 | tail -5
  ___x_cmd_CLAUDECODE_READY=1 . "$HOME/.x-cmd.root/X"
fi

which x || { echo "::error::x-cmd install failed"; exit 1; }
x --version