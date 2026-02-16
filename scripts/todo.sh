#!/usr/bin/env bash

set -u

get_tmux_option() {
  local option="$1"
  local default_value="$2"
  local option_value

  option_value="$(tmux show-option -gqv "$option")"

  if [ -z "$option_value" ]; then
    printf '%s' "$default_value"
  else
    printf '%s' "$option_value"
  fi
}

todo_file="$(get_tmux_option "@todo_file" "$HOME/.config/tmux/todo.md")"
archive_file="$(get_tmux_option "@todo_archive_file" "$HOME/.config/tmux/todo-archive.md")"

LOCK_HELD=0
lock_dir="${todo_file}.lockdir"

acquire_lock() {
  local tries=0

  while ! mkdir "$lock_dir" 2>/dev/null; do
    tries=$((tries + 1))
    if [ "$tries" -ge 200 ]; then
      printf 'Could not acquire write lock: %s\n' "$lock_dir" >&2
      exit 1
    fi
    sleep 0.05
  done

  LOCK_HELD=1
}

release_lock() {
  if [ "$LOCK_HELD" -eq 1 ]; then
    rmdir "$lock_dir" 2>/dev/null || true
    LOCK_HELD=0
  fi
}

ensure_storage_files() {
  local todo_parent_dir
  local archive_parent_dir

  todo_parent_dir="$(dirname "$todo_file")"
  archive_parent_dir="$(dirname "$archive_file")"

  mkdir -p "$todo_parent_dir"
  mkdir -p "$archive_parent_dir"

  if [ ! -f "$todo_file" ]; then
    touch "$todo_file"
  fi

  if [ ! -f "$archive_file" ]; then
    touch "$archive_file"
  fi
}

trap release_lock EXIT

declare -a TASK_STATUS=()
declare -a TASK_TEXT=()
declare -a TASK_CREATED=()
declare -a DISPLAY_ORDER=()

load_tasks() {
  TASK_STATUS=()
  TASK_TEXT=()
  TASK_CREATED=()

  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ ^-\ \[([\ xX])\]\ (.+)$ ]]; then
      local status_char="${BASH_REMATCH[1]}"
      local text="${BASH_REMATCH[2]}"
      local created_at=""

      if [[ "$text" =~ ^\[(P[123])\]\ (.+)$ ]]; then
        text="${BASH_REMATCH[2]}"
      fi

      if [[ "$text" =~ ^(.+)\ \<\!\-\-\ created:([^>]+)\ \-\-\>$ ]]; then
        text="${BASH_REMATCH[1]}"
        created_at="${BASH_REMATCH[2]}"
      fi

      if [ "$status_char" = "x" ] || [ "$status_char" = "X" ]; then
        status_char="x"
      else
        status_char=" "
      fi

      TASK_STATUS+=("$status_char")
      TASK_TEXT+=("$text")
      TASK_CREATED+=("$created_at")
    fi
  done < "$todo_file"
}

save_tasks_unlocked() {
  local temp_file

  temp_file="${todo_file}.tmp.$$"
  : > "$temp_file"

  local i
  for i in "${!TASK_TEXT[@]}"; do
    printf -- '- [%s] %s' "${TASK_STATUS[$i]}" "${TASK_TEXT[$i]}" >> "$temp_file"
    if [ -n "${TASK_CREATED[$i]}" ]; then
      printf -- ' <!-- created:%s -->' "${TASK_CREATED[$i]}" >> "$temp_file"
    fi
    printf '\n' >> "$temp_file"
  done

  mv "$temp_file" "$todo_file"
}

save_tasks() {
  acquire_lock
  save_tasks_unlocked
  release_lock
}

archive_task_unlocked() {
  local task_idx="$1"
  local archived_at

  archived_at="$(date '+%d/%m/%Y %H:%M')"

  printf -- '- [x] %s' "${TASK_TEXT[$task_idx]}" >> "$archive_file"
  if [ -n "${TASK_CREATED[$task_idx]}" ]; then
    printf -- ' <!-- created:%s -->' "${TASK_CREATED[$task_idx]}" >> "$archive_file"
  fi
  printf -- ' <!-- archived:%s -->\n' "$archived_at" >> "$archive_file"
}

delete_index() {
  local target="$1"
  local -a next_status=()
  local -a next_text=()
  local -a next_created=()

  local i
  for i in "${!TASK_TEXT[@]}"; do
    if [ "$i" -ne "$target" ]; then
      next_status+=("${TASK_STATUS[$i]}")
      next_text+=("${TASK_TEXT[$i]}")
      next_created+=("${TASK_CREATED[$i]}")
    fi
  done

  TASK_STATUS=("${next_status[@]}")
  TASK_TEXT=("${next_text[@]}")
  TASK_CREATED=("${next_created[@]}")
}

build_display_order() {
  DISPLAY_ORDER=()

  local i
  for i in "${!TASK_TEXT[@]}"; do
    if [ "${TASK_STATUS[$i]}" != "x" ]; then
      DISPLAY_ORDER+=("$i")
    fi
  done

  for i in "${!TASK_TEXT[@]}"; do
    if [ "${TASK_STATUS[$i]}" = "x" ]; then
      DISPLAY_ORDER+=("$i")
    fi
  done
}

find_display_pos_for_task() {
  local task_idx="$1"
  local pos

  for pos in "${!DISPLAY_ORDER[@]}"; do
    if [ "${DISPLAY_ORDER[$pos]}" -eq "$task_idx" ]; then
      printf '%s' "$pos"
      return
    fi
  done

  printf '0'
}

open_ui() {
  ensure_storage_files
  load_tasks
  build_display_order

  local cursor=0
  local show_created_option

  show_created_option="$(get_tmux_option "@todo_show_date" "on")"
  if [ "$show_created_option" = "off" ]; then
    show_created=0
  else
    show_created=1
  fi

  while true; do
    clear
    printf 'TODO LIST\n'
    printf 'j/k navigate | Enter toggle | a add | e edit | d delete | f date | q quit\n\n'

    if [ "${#DISPLAY_ORDER[@]}" -eq 0 ]; then
      printf 'No tasks\n'
    else
      local active_count=0
      local done_count=0
      local i

      for i in "${!TASK_TEXT[@]}"; do
        if [ "${TASK_STATUS[$i]}" = "x" ]; then
          done_count=$((done_count + 1))
        else
          active_count=$((active_count + 1))
        fi
      done

      local divider_printed=0
      local row
      for row in "${!DISPLAY_ORDER[@]}"; do
        local task_idx="${DISPLAY_ORDER[$row]}"
        local pointer=" "

        if [ "$row" -eq "$cursor" ]; then
          pointer=">"
        fi

        if [ "$divider_printed" -eq 0 ] && [ "$active_count" -gt 0 ] && [ "$done_count" -gt 0 ] && [ "${TASK_STATUS[$task_idx]}" = "x" ]; then
          printf -- '--------------------- Completed ---------------------\n'
          divider_printed=1
        fi

        printf '%s [%s] %s' "$pointer" "${TASK_STATUS[$task_idx]}" "${TASK_TEXT[$task_idx]}"
        if [ "$show_created" -eq 1 ] && [ -n "${TASK_CREATED[$task_idx]}" ]; then
          printf ' \033[2;3m(%s)\033[0m' "${TASK_CREATED[$task_idx]}"
        fi
        printf '\n'
      done
    fi

    IFS= read -rsn1 key || true

    if [ -z "$key" ]; then
      key=$'\n'
    fi

    if [ "$key" = $'\r' ]; then
      key=$'\n'
    fi

    if [ "$key" = $'\x1b' ]; then
      read -rsn2 -t 0.01 key_rest || true
      key+="$key_rest"
    fi

    case "$key" in
      q)
        exit 0
        ;;
      j|$'\x1b[B')
        if [ "${#DISPLAY_ORDER[@]}" -gt 0 ] && [ "$cursor" -lt "$(( ${#DISPLAY_ORDER[@]} - 1 ))" ]; then
          cursor=$((cursor + 1))
        fi
        ;;
      k|$'\x1b[A')
        if [ "$cursor" -gt 0 ]; then
          cursor=$((cursor - 1))
        fi
        ;;
      $'\n')
        if [ "${#DISPLAY_ORDER[@]}" -gt 0 ]; then
          local previous_cursor="$cursor"
          local task_idx="${DISPLAY_ORDER[$cursor]}"

          if [ "${TASK_STATUS[$task_idx]}" = "x" ]; then
            TASK_STATUS[$task_idx]=" "
          else
            TASK_STATUS[$task_idx]="x"
          fi

          save_tasks
          build_display_order

          if [ "${#DISPLAY_ORDER[@]}" -eq 0 ]; then
            cursor=0
          elif [ "$previous_cursor" -ge "${#DISPLAY_ORDER[@]}" ]; then
            cursor=$(( ${#DISPLAY_ORDER[@]} - 1 ))
          else
            cursor="$previous_cursor"
          fi

          [ "$cursor" -ge "${#DISPLAY_ORDER[@]}" ] && cursor=$(( ${#DISPLAY_ORDER[@]} - 1 ))
          [ "$cursor" -lt 0 ] && cursor=0
        fi
        ;;
      d|$'\x04')
        if [ "${#DISPLAY_ORDER[@]}" -gt 0 ]; then
          local delete_target_idx="${DISPLAY_ORDER[$cursor]}"
          local delete_target_text="${TASK_TEXT[$delete_target_idx]}"

          printf '\nDelete task: "%s"? [y/N]: ' "$delete_target_text"
          IFS= read -r confirm_delete

          if [ "$confirm_delete" = "y" ] || [ "$confirm_delete" = "Y" ]; then
            acquire_lock
            archive_task_unlocked "$delete_target_idx"
            delete_index "$delete_target_idx"
            save_tasks_unlocked
            release_lock

            build_display_order
            [ "$cursor" -ge "${#DISPLAY_ORDER[@]}" ] && cursor=$(( ${#DISPLAY_ORDER[@]} - 1 ))
            [ "$cursor" -lt 0 ] && cursor=0
          fi
        fi
        ;;
      a)
        printf '\nNew task: '
        IFS= read -r new_text

        if [ -n "$new_text" ]; then
          local created_now
          created_now="$(date '+%d/%m/%Y %H:%M')"

          TASK_STATUS+=(" ")
          TASK_TEXT+=("$new_text")
          TASK_CREATED+=("$created_now")

          save_tasks
          build_display_order
          cursor="$(find_display_pos_for_task "$(( ${#TASK_TEXT[@]} - 1 ))")"
          [ "$cursor" -lt 0 ] && cursor=0
        fi
        ;;
      e)
        if [ "${#DISPLAY_ORDER[@]}" -gt 0 ]; then
          local edit_idx="${DISPLAY_ORDER[$cursor]}"
          local old_text="${TASK_TEXT[$edit_idx]}"

          printf '\nEditing current task: %s\n' "$old_text"
          printf 'New text (empty cancels): '
          IFS= read -r edited_text

          if [ -n "$edited_text" ]; then
            TASK_TEXT[$edit_idx]="$edited_text"
            save_tasks
            build_display_order
            cursor="$(find_display_pos_for_task "$edit_idx")"
            [ "$cursor" -lt 0 ] && cursor=0
          fi
        fi
        ;;
      f)
        if [ "$show_created" -eq 1 ]; then
          show_created=0
          tmux set-option -gq "@todo_show_date" "off"
        else
          show_created=1
          tmux set-option -gq "@todo_show_date" "on"
        fi
        ;;
    esac
  done
}

open_popup() {
  local self_path

  self_path="$(realpath "$0")"

  if tmux display-popup -E "bash '$self_path' ui" 2>/dev/null; then
    return 0
  fi

  tmux split-window -v -p 40 "bash '$self_path' ui"
}

main() {
  local command="${1:-open}"

  case "$command" in
    open)
      open_popup
      ;;
    ui)
      open_ui
      ;;
    *)
      printf 'Unsupported command: %s\n' "$command" >&2
      exit 1
      ;;
  esac
}

main "$@"
