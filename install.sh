#!/usr/bin/env bash
set -euo pipefail

APP_ID="boot-to-windows"
APP_NAME="Boot to Windows"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
XDG_DATA_HOME="${XDG_DATA_HOME:-"$HOME/.local/share"}"
BIN_DIR="$HOME/.local/bin"
APP_DIR="$XDG_DATA_HOME/applications"
ICON_DIR="$XDG_DATA_HOME/icons/hicolor/scalable/apps"
ICON_THEME_DIR="$XDG_DATA_HOME/icons/hicolor"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: ./install.sh [--dry-run]

Install boot-to-windows for the current user:
  ~/.local/bin/boot-to-windows
  ~/.local/share/applications/boot-to-windows.desktop
  ~/.local/share/icons/hicolor/scalable/apps/boot-to-windows.svg
EOF
}

desktop_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}

run() {
  if (( DRY_RUN == 1 )); then
    printf '+'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

write_desktop_file() {
  local desktop_file="$APP_DIR/$APP_ID.desktop"
  local exec_line
  exec_line="$(desktop_quote "$BIN_DIR/$APP_ID")"

  if (( DRY_RUN == 1 )); then
    printf '+ write %q\n' "$desktop_file"
    return
  fi

  mkdir -p "$APP_DIR"
  cat > "$desktop_file" <<EOF
[Desktop Entry]
Type=Application
Name=$APP_NAME
Name[ru]=Перезагрузиться в Windows
Comment=Set Windows as the next boot target and reboot
Comment[ru]=Выбрать Windows для следующей загрузки и перезагрузиться
Exec=$exec_line
Icon=$APP_ID
Terminal=false
Categories=System;
Keywords=Windows;Reboot;Boot;Dual Boot;Перезагрузка;Загрузка;
StartupNotify=false
EOF
  chmod 0644 "$desktop_file"
}

main() {
  while (($#)); do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        printf 'Unknown option: %s\n' "$1" >&2
        usage >&2
        exit 1
        ;;
    esac
    shift
  done

  run install -Dm755 "$SCRIPT_DIR/$APP_ID" "$BIN_DIR/$APP_ID"
  run install -Dm644 "$SCRIPT_DIR/icons/$APP_ID.svg" "$ICON_DIR/$APP_ID.svg"
  write_desktop_file

  if (( DRY_RUN == 0 )); then
    if command -v desktop-file-validate >/dev/null 2>&1; then
      desktop-file-validate "$APP_DIR/$APP_ID.desktop"
    fi

    if command -v update-desktop-database >/dev/null 2>&1; then
      update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
    fi

    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
      gtk-update-icon-cache -q "$ICON_THEME_DIR" >/dev/null 2>&1 || true
    fi

    printf 'Installed %s. It should appear in the application menu as "%s".\n' "$APP_ID" "$APP_NAME"
  fi
}

main "$@"
