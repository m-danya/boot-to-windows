#!/usr/bin/env bash
set -euo pipefail

APP_ID="boot-to-windows"
APP_NAME="Boot to Windows"
POLKIT_ACTION_ID="com.m-danya.boot-to-windows.reboot"
POLKIT_POLICY_ID="com.m-danya.boot-to-windows"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
XDG_DATA_HOME="${XDG_DATA_HOME:-"$HOME/.local/share"}"
BIN_DIR="$HOME/.local/bin"
APP_DIR="$XDG_DATA_HOME/applications"
ICON_DIR="$XDG_DATA_HOME/icons/hicolor/scalable/apps"
ICON_THEME_DIR="$XDG_DATA_HOME/icons/hicolor"
PRIVILEGED_DIR="/usr/local/libexec/$APP_ID"
PRIVILEGED_BIN="$PRIVILEGED_DIR/$APP_ID"
POLKIT_POLICY_DIR="/usr/local/share/polkit-1/actions"
POLKIT_POLICY_FILE="$POLKIT_POLICY_DIR/$POLKIT_POLICY_ID.policy"
POLKIT_RULES_DIR="/etc/polkit-1/rules.d"
POLKIT_RULE_FILE="$POLKIT_RULES_DIR/49-$APP_ID.rules"
DRY_RUN=0
INSTALL_PRIVILEGED=1
PRIVILEGED_ONLY=0
TARGET_USER=""

usage() {
  cat <<'EOF'
Usage: ./install.sh [--dry-run] [--no-polkit]

Install boot-to-windows for the current user:
  ~/.local/bin/boot-to-windows
  ~/.local/share/applications/boot-to-windows.desktop
  ~/.local/share/icons/hicolor/scalable/apps/boot-to-windows.svg

By default, the installer also sets up a root-owned pkexec helper and a polkit
rule so the desktop launcher can reboot into Windows without asking for a
password after installation. Use --no-polkit to skip that system setup.
EOF
}

desktop_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}

js_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\n'/\\n}"
  printf '"%s"' "$value"
}

default_target_user() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER:-}" != "root" ]]; then
    printf '%s\n' "$SUDO_USER"
    return
  fi

  id -un
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

write_polkit_policy_file() {
  mkdir -p "$POLKIT_POLICY_DIR"
  cat > "$POLKIT_POLICY_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE policyconfig PUBLIC
 "-//freedesktop//DTD polkit Policy Configuration 1.0//EN"
 "http://www.freedesktop.org/software/polkit/policyconfig-1.dtd">
<policyconfig>
  <vendor>$APP_NAME</vendor>
  <icon_name>$APP_ID</icon_name>

  <action id="$POLKIT_ACTION_ID">
    <description>Reboot into Windows</description>
    <description xml:lang="ru">Перезагрузиться в Windows</description>
    <message>Authentication is required to set Windows as the next boot target and reboot.</message>
    <message xml:lang="ru">Нужна авторизация, чтобы выбрать Windows для следующей загрузки и перезагрузиться.</message>
    <defaults>
      <allow_any>auth_admin</allow_any>
      <allow_inactive>auth_admin</allow_inactive>
      <allow_active>auth_admin</allow_active>
    </defaults>
    <annotate key="org.freedesktop.policykit.exec.path">$PRIVILEGED_BIN</annotate>
  </action>
</policyconfig>
EOF
  chmod 0644 "$POLKIT_POLICY_FILE"
}

write_polkit_rule_file() {
  local target_user="$1"
  local target_user_js
  target_user_js="$(js_quote "$target_user")"

  mkdir -p "$POLKIT_RULES_DIR"
  cat > "$POLKIT_RULE_FILE" <<EOF
polkit.addRule(function(action, subject) {
  if (action.id == "$POLKIT_ACTION_ID" &&
      subject.user == $target_user_js &&
      subject.local &&
      subject.active) {
    return polkit.Result.YES;
  }
});
EOF
  chmod 0644 "$POLKIT_RULE_FILE"
}

install_privileged_as_root() {
  local target_user="$1"

  if (( EUID != 0 )); then
    printf 'Privileged setup must run as root.\n' >&2
    return 1
  fi

  if (( DRY_RUN == 1 )); then
    printf '+ install -Dm755 %q %q\n' "$SCRIPT_DIR/$APP_ID" "$PRIVILEGED_BIN"
    printf '+ write %q\n' "$POLKIT_POLICY_FILE"
    printf '+ write %q for user %q\n' "$POLKIT_RULE_FILE" "$target_user"
    return
  fi

  install -Dm755 "$SCRIPT_DIR/$APP_ID" "$PRIVILEGED_BIN"
  write_polkit_policy_file
  write_polkit_rule_file "$target_user"
}

install_privileged() {
  local target_user="$1"
  local -a cmd=("$SCRIPT_DIR/install.sh" --privileged-only --target-user "$target_user")

  if (( DRY_RUN == 1 )); then
    printf '+ privileged setup for user %q\n' "$target_user"
    printf '+'
    printf ' %q' "${cmd[@]}"
    printf '\n'
    return
  fi

  if (( EUID == 0 )); then
    install_privileged_as_root "$target_user"
    return
  fi

  printf 'Installing passwordless desktop helper. One-time authentication may be required.\n'
  if command -v pkexec >/dev/null 2>&1; then
    pkexec "${cmd[@]}"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "${cmd[@]}"
  else
    printf 'Could not find pkexec or sudo. Re-run with sudo or use --no-polkit.\n' >&2
    return 1
  fi
}

main() {
  TARGET_USER="$(default_target_user)"

  while (($#)); do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        ;;
      --no-polkit)
        INSTALL_PRIVILEGED=0
        ;;
      --privileged-only)
        PRIVILEGED_ONLY=1
        ;;
      --target-user)
        shift
        [[ $# -gt 0 ]] || {
          printf '%s\n' '--target-user needs a value' >&2
          exit 1
        }
        TARGET_USER="$1"
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

  if (( PRIVILEGED_ONLY == 1 )); then
    install_privileged_as_root "$TARGET_USER"
    exit 0
  fi

  run install -Dm755 "$SCRIPT_DIR/$APP_ID" "$BIN_DIR/$APP_ID"
  run install -Dm644 "$SCRIPT_DIR/icons/$APP_ID.svg" "$ICON_DIR/$APP_ID.svg"
  write_desktop_file
  if (( INSTALL_PRIVILEGED == 1 )); then
    install_privileged "$TARGET_USER"
  fi

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
