#!/usr/bin/env bash
#
# Focus-TV Installer (based on Lampac NextGen)
# Downloads release zip, creates system user, installs .NET 10 + OS deps,
# registers systemd unit, and applies Focus-TV default config.
#
set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly INSTALL_ROOT="${LAMPAC_INSTALL_ROOT:-/opt/lampac}"
readonly LAMPAC_USER="${LAMPAC_USER:-lampac}"
readonly SERVICE_NAME="${LAMPAC_SERVICE_NAME:-lampac}"
readonly SYSTEMD_UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
readonly GITHUB_REPO="${LAMPAC_GITHUB_REPO:-bolshik/my-lampac}"
readonly RELEASE_ZIP_NAME="lampac-nextgen.zip"
readonly DOTNET_INSTALL_DIR="${LAMPAC_DOTNET_ROOT:-/usr/share/dotnet}"
readonly DOTNET_CHANNEL="${LAMPAC_DOTNET_CHANNEL:-10.0}"
readonly LISTEN_PORT="${LAMPAC_PORT:-9118}"
readonly UPDATE_SCRIPT_NAME="install.sh"

REMOVE=0; UPDATE=0; DRY_RUN=0; PRE_RELEASE=0; VERBOSE=0
ARCH=""; PUBLISH_URL=""; CLEANUP_PATHS=()

_tty_escape() { printf '\033[%sm' "$1"; }
if [[ -t 1 ]]; then
  C_RESET=$(_tty_escape 0); C_BOLD=$(_tty_escape 1); C_DIM=$(_tty_escape 2)
  C_RED=$(_tty_escape "1;31"); C_GREEN=$(_tty_escape "1;32"); C_YELLOW=$(_tty_escape "1;33")
  C_BLUE=$(_tty_escape "1;34"); C_CYAN=$(_tty_escape "1;36"); C_WHITE=$(_tty_escape "1;37")
  C_GRAY=$(_tty_escape "0;37")
else
  C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW=""
  C_BLUE="" C_CYAN="" C_WHITE="" C_GRAY=""
fi

log_info()  { printf '  %s→%s  %s\n'     "$C_BLUE"   "$C_RESET" "$*"; }
log_ok()    { printf '  %s✓%s  %s\n'     "$C_GREEN"  "$C_RESET" "$*"; }
log_warn()  { printf '  %s⚠%s  %s\n'     "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_err()   { printf '  %s✗%s  %s\n'     "$C_RED"    "$C_RESET" "$*" >&2; }
log_skip()  { printf '  %s·%s  %s%s%s\n' "$C_GRAY"   "$C_RESET" "$C_DIM" "$*" "$C_RESET"; }

print_banner() {
  printf '\n'
  printf '███████╗ ██████╗  ██████╗██╗   ██╗███████╗   ████████╗██╗   ██╗\n'
  printf '██╔════╝██╔═══██╗██╔════╝██║   ██║██╔════╝   ╚══██╔══╝██║   ██║\n'
  printf '█████╗  ██║   ██║██║     ██║   ██║███████╗█████╗██║   ██║   ██║\n'
  printf '██╔══╝  ██║   ██║██║     ██║   ██║╚════██║╚════╝██║   ╚██╗ ██╔╝\n'
  printf '██║     ╚██████╔╝╚██████╗╚██████╔╝███████║      ██║    ╚████╔╝ \n'
  printf '╚═╝      ╚═════╝  ╚═════╝ ╚═════╝ ╚══════╝      ╚═╝     ╚═══╝  \n'
  printf '\n'
}

detect_arch() {
  case "$(uname -m)" in
    x86_64) echo "amd64" ;; aarch64|arm64) echo "arm64" ;;
    *) log_err "Unsupported arch: $(uname -m)"; exit 1 ;;
  esac
}

pick_libicu_package() {
  for p in libicu78 libicu76 libicu74 libicu72 libicu70 libicu67; do
    apt-cache show "$p" &>/dev/null && { echo "$p"; return 0; }
  done
  log_err "No libicu package found"; exit 1
}

is_ubuntu() {
  [[ -r /etc/os-release ]] && { . /etc/os-release; [[ "${ID:-}" == "ubuntu" ]]; }
}

# ─── Install steps ───────────────────────────────────────────────────────────

install_os_packages() {
  apt-get update -qq
  if is_ubuntu; then
    apt-get install -y -qq software-properties-common 2>/dev/null || true
    add-apt-repository -y ppa:xtradeb/apps -qq 2>/dev/null || true
    apt-get update -qq
  fi
  local icu_pkg=$(pick_libicu_package)
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates curl chromium fontconfig libnspr4 unzip "$icu_pkg"
  apt-get clean -qq; rm -rf /var/lib/apt/lists/*
}

install_aspnetcore_runtime() {
  if [[ -x "${DOTNET_INSTALL_DIR}/dotnet" ]] \
    && "${DOTNET_INSTALL_DIR}/dotnet" --list-runtimes 2>/dev/null | grep -q 'Microsoft.AspNetCore.App 10.'; then
    log_skip "ASP.NET Core 10 runtime already present"
    return 0
  fi
  local installer="/tmp/dotnet-install-$$.sh"
  curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$installer"
  chmod +x "$installer"
  bash "$installer" --channel "$DOTNET_CHANNEL" --runtime aspnetcore --install-dir "$DOTNET_INSTALL_DIR"
  rm -f "$installer"
}

ensure_service_user() {
  local uid="${LAMPAC_UID:-1000}" gid="${LAMPAC_GID:-1000}"
  getent group "$LAMPAC_USER" &>/dev/null || groupadd -r -g "$gid" "$LAMPAC_USER" 2>/dev/null || groupadd -r "$LAMPAC_USER"
  getent passwd "$LAMPAC_USER" &>/dev/null || useradd -r -u "$uid" -g "$LAMPAC_USER" -d "$INSTALL_ROOT" -s /usr/sbin/nologin "$LAMPAC_USER" 2>/dev/null || useradd -r -g "$LAMPAC_USER" -d "$INSTALL_ROOT" -s /usr/sbin/nologin "$LAMPAC_USER"
}

set_ownership() { chown -R "${LAMPAC_USER}:${LAMPAC_USER}" "$INSTALL_ROOT"; }

install_app() {
  local tmp_zip="/tmp/lampac-nextgen-$$.zip"
  curl -fSL --retry 3 -o "$tmp_zip" "$PUBLISH_URL"
  mkdir -p "$INSTALL_ROOT"
  unzip -oq "$tmp_zip" -d "$INSTALL_ROOT"
  rm -f "$tmp_zip"
}

install_systemd_unit() {
  cat << EOF > "$SYSTEMD_UNIT_PATH"
[Unit]
Description=Focus-TV (Lampac NextGen)
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=$LAMPAC_USER
Group=$LAMPAC_USER
WorkingDirectory=$INSTALL_ROOT
Environment=DOTNET_ROOT=$DOTNET_INSTALL_DIR
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$DOTNET_INSTALL_DIR
Environment=DOTNET_RUNNING_IN_CONTAINER=false
Environment=DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false
Environment=CHROMIUM_PATH=/usr/bin/chromium
Environment=CHROMIUM_FLAGS=--no-sandbox --disable-setuid-sandbox --disable-dev-shm-usage
ExecStart=$DOTNET_INSTALL_DIR/dotnet $INSTALL_ROOT/Core.dll
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  chmod 644 "$SYSTEMD_UNIT_PATH"
  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
}

configure_focus_tv() {
  # Пароль администратора
  echo -n "Vfhifk1981@" | tee "${INSTALL_ROOT}/passwd" > /dev/null
  chown "${LAMPAC_USER}:${LAMPAC_USER}" "${INSTALL_ROOT}/passwd"

  # Правильный init.conf
  cat > "${INSTALL_ROOT}/init.conf" << 'INITEOF'
{
  "WebLog": {
    "enable": false,
    "password": "Vfhifk1981@"
  },
  "BaseModule": {
    "SkipModules": [
      "DLNA", "Catalog", "SyncEvents", "Storage",
      "Tracks", "Transcoding", "WebLog", "TelegramAuth", "TelegramAuthBot"
    ],
    "LoadModules": [ "AdminPanel", ".*" ]
  },
  "AdminPanel": {
    "enable": true,
    "password": "Vfhifk1981@"
  },
  "WAF": {
    "enable": true
  },
  "accsdb": {
    "enable": true,
    "autoreg": true
  },
  "online": {
    "name": "Lampac NextGen",
    "version": true,
    "btn_priority_forced": true
  },
  "LampaWeb": {
    "initPlugins": {
      "online": true,
      "sisi": true,
      "torrserver": true,
      "timecode": true,
      "jacred": true,
      "tmdbProxy": true,
      "cubProxy": true
    }
  },
  "listen": {
    "port": 9118
  }
}
INITEOF
  chown "${LAMPAC_USER}:${LAMPAC_USER}" "${INSTALL_ROOT}/init.conf"

  # Включаем AdminPanel
  mkdir -p "${INSTALL_ROOT}/mods"
  cp -r "${INSTALL_ROOT}/module/AdminPanel" "${INSTALL_ROOT}/mods/AdminPanel"
  sed -i 's/"enable": false/"enable": true/' "${INSTALL_ROOT}/mods/AdminPanel/manifest.json"
  chown -R "${LAMPAC_USER}:${LAMPAC_USER}" "${INSTALL_ROOT}/mods"
}

start_service() { systemctl start "$SERVICE_NAME"; }

print_success() {
  local ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  [[ -z "$ip" ]] && ip="<your-ip>"
  printf '\n%s  ─── Focus-TV installed! ───%s\n' "$C_GREEN" "$C_RESET"
  printf '  URL:    http://%s:%s\n' "$ip" "$LISTEN_PORT"
  printf '  Admin:  http://%s:%s/adminpanel/  (login: any, pass: Vfhifk1981@)\n' "$ip" "$LISTEN_PORT"
  printf '  Config: %s/init.conf\n' "$INSTALL_ROOT"
  printf '  Logs:   journalctl -u %s -f\n\n' "$SERVICE_NAME"
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
  if [[ ${EUID} -ne 0 ]]; then exec sudo -E "$0" "$@"; fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --remove) REMOVE=1; shift ;;
      --update) UPDATE=1; shift ;;
      --verbose|-v) VERBOSE=1; shift ;;
      *) log_err "Unknown: $1"; exit 1 ;;
    esac
  done

  ARCH=$(detect_arch)
  PUBLISH_URL="https://github.com/${GITHUB_REPO}/releases/latest/download/${RELEASE_ZIP_NAME}"

  if [[ "$REMOVE" -eq 1 ]]; then
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    rm -f "$SYSTEMD_UNIT_PATH"
    systemctl daemon-reload
    rm -rf "$INSTALL_ROOT"
    userdel "$LAMPAC_USER" 2>/dev/null || true
    groupdel "$LAMPAC_USER" 2>/dev/null || true
    log_ok "Focus-TV removed"
    exit 0
  fi

  print_banner
  printf '  Mode:  %s\n' "$([[ $UPDATE -eq 1 ]] && echo "Update" || echo "Install")"
  printf '  Arch:  %s\n' "$ARCH"
  printf '  Dir:   %s\n' "$INSTALL_ROOT"
  printf '\n'

  install_os_packages
  install_aspnetcore_runtime

  if [[ "$UPDATE" -eq 1 ]]; then
    install_app
    set_ownership
    systemctl restart "$SERVICE_NAME"
    log_ok "Focus-TV updated"
    exit 0
  fi

  ensure_service_user
  install_app
  install_systemd_unit
  configure_focus_tv
  set_ownership
  start_service
  print_success
}

main "$@"
