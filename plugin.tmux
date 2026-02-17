#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

todo_key="$(tmux show-option -gqv "@todo_key")"
[ -z "$todo_key" ] && todo_key="T"

tmux bind-key "$todo_key" run-shell "$CURRENT_DIR/scripts/todo.sh open"
