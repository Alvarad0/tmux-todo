# tmux-todo

A lightweight tmux todo list plugin with Markdown persistence.

## Features

- Configurable todo file path with `@todo_file`
- Configurable archive file path with `@todo_archive_file`
- Toggle tasks with `Enter`
- Add tasks with `a`
- Edit tasks with `e`
- Archive tasks with `d` / `Ctrl-d` (with confirmation)
- Show active tasks first, completed tasks below with a divider
- Store creation timestamp per task
- Show dates by default, toggle with `f` (persisted with `@todo_show_date`)
- Write lock to avoid corruption in concurrent sessions

## Task Format

Tasks are stored in Markdown as:

```md
- [ ] Prepare sales report <!-- created:16/02/2026 11:23 -->
- [x] Send PO to supplier <!-- created:16/02/2026 11:30 -->
```

Archived tasks include archive metadata:

```md
- [x] Send PO to supplier <!-- created:16/02/2026 11:30 --> <!-- archived:16/02/2026 12:10 -->
```

## Installation

### With TPM

In `~/.tmux.conf`:

```tmux
set -g @plugin 'alvarad0/tmux-todo'
```

Reload tmux and install plugins with `prefix + I`.

### Manual

Clone the repository and source `plugin.tmux` from your `~/.tmux.conf`.

## Configuration

Add this to `~/.tmux.conf`:

```tmux
set -g @todo_key 'T'
set -g @todo_file '$HOME/.config/tmux/todo.md'
set -g @todo_archive_file '$HOME/.config/tmux/todo-archive.md'
set -g @todo_show_date 'on'
```

## Usage

- `prefix + T`: open todo UI
- `j` / `k` or arrows: move selection
- `Enter`: toggle complete/incomplete
- `a`: add task
- `e`: edit selected task
- `d` or `Ctrl-d`: archive selected task (confirm)
- `f`: toggle date visibility
- `q`: quit
