#!/usr/bin/env bash
#
# Zephyr Music Client - interactive installer for Linux
#
# - Lets you choose where to install (user-local, system-wide, or custom).
# - Detects a previous install and asks before updating it, including the
#   case where the same version is already installed.
# - Works from a source checkout (builds with Flutter if needed) or from a
#   distributed bundle placed beside this script (bundle/ or ./frontend).
#
set -Eeuo pipefail

APP_NAME="Zephyr Music Client"
APP_ID="com.giorgiotassoni.zephyr"
BINARY_NAME="frontend"
RELEASE_CHANNEL="${RELEASE_CHANNEL:-Preview}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="${SCRIPT_DIR}/apps/zephyr_desktop"
DEFAULT_BUNDLE="${APP_ROOT}/build/linux/x64/release/bundle"
META_FILE=".zephyr-version"          # written into the install dir

INSTALL_DIR="${ZEPHYR_INSTALL_DIR:-}"
BUNDLE_DIR=""
YES_MODE=0
FORCE_MODE=0
UNINSTALL_MODE=0
INSTALL_DIR_SET=0
[[ -n "${ZEPHYR_INSTALL_DIR:-}" ]] && INSTALL_DIR_SET=1
INTERACTIVE=0
[[ -t 0 && -t 1 ]] && INTERACTIVE=1
SUDO=""

usage() {
  cat <<EOF
Usage:
  ./installSelect.sh [options] [bundle-directory]
  ./installSelect.sh --uninstall [options]

Interactive Linux installer for ${APP_NAME}. It asks where to install and,
when a previous install is found, asks whether to update it.

Options:
  -d, --dir DIR       Install into DIR (default: ~/.local/opt/zephyr).
  -b, --bundle DIR    Use this Flutter Linux bundle (frontend + data/ + lib/).
  -y, --yes           Answer yes to update/overwrite prompts.
  -f, --force         Same as --yes; also allow reinstalling the same version.
  -c, --channel NAME  Release channel label (default: \${RELEASE_CHANNEL:-Preview}).
  -u, --uninstall     Remove the install found in --dir (or the default).
  -h, --help          Show this help.

bundle-directory defaults to, in order:
  1. apps/zephyr_desktop/build/linux/x64/release/bundle (source checkout)
  2. bundle/ next to this script (distributed bundle)
  3. the directory containing this script, if frontend + data/ + lib/ are there
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

# --- small helpers -----------------------------------------------------------

# run [cmd...] - execute with sudo when the target needs admin rights
run() {
  if [[ -n "${SUDO}" ]]; then
    "${SUDO}" "$@"
  else
    "$@"
  fi
}

prompt_confirm() {
  # prompt_confirm MESSAGE DEFAULT(Y|N) -> 0 yes, 1 no
  local msg="$1" dflt="$2" ans
  if (( YES_MODE || FORCE_MODE )); then
    echo "${msg} [${dflt}]: yes (auto)"
    return 0
  fi
  if (( ! INTERACTIVE )); then
    echo "${msg} [${dflt}]: no (non-interactive)" >&2
    return 1
  fi
  while true; do
    read -r -p "${msg} [${dflt}] " ans
    case "${ans:-}" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) return 1 ;;
      "") [[ "${dflt}" == "Y" ]] && return 0 || return 1 ;;
      *) echo "Please answer y or n." ;;
    esac
  done
}

expand_path() {
  local p="$1"
  p="${p/#\~/$HOME}"
  echo "${p%/}"
}

version_newer() {
  # version_newer A B -> 0 if A > B (semver-ish, sort -V)
  [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" != "$1" ]]
}

# --- argument parsing --------------------------------------------------------

while [[ "${#}" -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -u|--uninstall) UNINSTALL_MODE=1 ;;
    -y|--yes) YES_MODE=1 ;;
    -f|--force) YES_MODE=1; FORCE_MODE=1 ;;
    -d|--dir) INSTALL_DIR="${2:?--dir needs a path}"; INSTALL_DIR_SET=1; shift ;;
    --dir=*) INSTALL_DIR="${1#*=}" ;;
    -b|--bundle) BUNDLE_DIR="${2:?--bundle needs a path}"; shift ;;
    --bundle=*) BUNDLE_DIR="${1#*=}" ;;
    -c|--channel) RELEASE_CHANNEL="${2:?--channel needs a NAME}"; shift ;;
    --channel=*) RELEASE_CHANNEL="${1#*=}" ;;
    --) shift; break ;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) [[ -z "${BUNDLE_DIR}" ]] && BUNDLE_DIR="$1" || die "too many arguments";;
  esac
  shift
done

if [[ -z "${INSTALL_DIR}" ]]; then
  INSTALL_DIR="${HOME}/.local/opt/zephyr"
fi
INSTALL_DIR="$(expand_path "${INSTALL_DIR}")"

# --- locate the bundle --------------------------------------------------------

locate_bundle() {
  local cand
  for cand in \
    "${BUNDLE_DIR}" \
    "${SCRIPT_DIR}/bundle" \
    "${SCRIPT_DIR}" \
    "${DEFAULT_BUNDLE}"
  do
    [[ -z "${cand}" ]] && continue
    if [[ -x "${cand}/${BINARY_NAME}" && -d "${cand}/data" && -d "${cand}/lib" ]]; then
      BUNDLE_DIR="${cand}"
      return 0
    fi
  done

  if (( INTERACTIVE )); then
    read -r -p "Where is the Zephyr bundle (directory containing ${BINARY_NAME}, data/, lib/)? " cand
    cand="$(expand_path "${cand:-}")"
    if [[ -x "${cand}/${BINARY_NAME}" && -d "${cand}/data" && -d "${cand}/lib" ]]; then
      BUNDLE_DIR="${cand}"
      return 0
    fi
    die "not a valid Zephyr bundle: ${cand}"
  fi

  die "could not find a Zephyr bundle. Build one with:" \
      "flutter build linux --release --dart-define=RELEASE_CHANNEL=${RELEASE_CHANNEL}" \
      "or place bundle/ next to this script."
}

# --- version detection ---------------------------------------------------------

new_version() {
  # Prefer a VERSION marker shipped with the bundle ("1.1.0\nChannel"),
  # then fall back to pubspec.yaml in a source checkout.
  if [[ -f "${BUNDLE_DIR}/VERSION" ]]; then
    sed -n '1p' "${BUNDLE_DIR}/VERSION" | tr -d '[:space:]'
  elif [[ -f "${APP_ROOT}/pubspec.yaml" ]]; then
    sed -n 's/^version:[[:space:]]*\([^+[:space:]]*\).*/\1/p' "${APP_ROOT}/pubspec.yaml" | head -n1 | tr -d '[:space:]'
  else
    echo "unknown"
  fi
}

new_channel() {
  if [[ -f "${BUNDLE_DIR}/VERSION" ]]; then
    local line2
    line2="$(sed -n '2p' "${BUNDLE_DIR}/VERSION" | tr -d '[:space:]')"
    [[ -n "${line2}" ]] && echo "${line2}" || echo "${RELEASE_CHANNEL}"
  else
    echo "${RELEASE_CHANNEL}"
  fi
}

installed_version() {
  if [[ -f "${INSTALL_DIR}/${META_FILE}" ]]; then
    awk '{print $1}' "${INSTALL_DIR}/${META_FILE}"
  elif [[ -x "${INSTALL_DIR}/${BINARY_NAME}" ]]; then
    echo "present"
  else
    echo "none"
  fi
}

# --- choose the install directory ---------------------------------------------

select_install_dir() {
  local def="${HOME}/.local/opt/zephyr" choice custom
  # Already chosen via ZEPHYR_INSTALL_DIR or --dir: keep it
  if (( INSTALL_DIR_SET )); then
    INSTALL_DIR="$(expand_path "${INSTALL_DIR}")"
    return
  fi
  if (( ! INTERACTIVE )); then
    INSTALL_DIR="$(expand_path "${INSTALL_DIR}")"
    return
  fi

  echo
  echo "Where should ${APP_NAME} be installed?"
  echo "  1) ${def}      (user-local, no admin rights)"
  echo "  2) /opt/zephyr (system-wide, sudo will be used)"
  echo "  3) Custom path"
  while true; do
    read -r -p "Choose [1/2/3, default 1]: " choice
    case "${choice:-1}" in
      1) INSTALL_DIR="${def}" ;;
      2) INSTALL_DIR="/opt/zephyr" ;;
      3)
        read -r -p "Custom path: " custom
        if [[ -n "${custom:-}" ]]; then
          INSTALL_DIR="$(expand_path "${custom}")"
        else
          echo "Empty path, keeping ${INSTALL_DIR}."; return
        fi
        ;;
      *) echo "Please choose 1, 2 or 3."; continue ;;
    esac
    return
  done
}

setup_privileges() {
  if [[ "$(id -u)" -eq 0 ]]; then SUDO=""; return; fi
  # find the deepest existing ancestor to test writability (e.g. fresh
  # /opt/zephyr -> /opt may not exist yet -> walk up to /)
  local probe="${INSTALL_DIR}"
  while [[ ! -e "${probe}" && "${probe}" != "/" ]]; do
    probe="$(dirname -- "${probe}")"
  done
  if [[ -w "${probe}" ]]; then SUDO=""; return; fi
  if (( INTERACTIVE )); then
    if prompt_confirm "The install directory (${INSTALL_DIR}) needs admin rights. Use sudo?" "Y"; then
      SUDO="sudo"
    else
      die "pick a directory you can write to, or run with sudo"
    fi
  else
    SUDO="sudo"
  fi
}

# --- confirm update when something is already installed --------------------------

confirm_before_install() {
  local inst newv
  inst="$(installed_version)"
  newv="${NEW_VERSION}"

  if [[ "${inst}" == "none" ]]; then
    return 0
  fi

  # Present but no version metadata (e.g. installed by the old script)
  if [[ "${inst}" == "present" || "${inst}" == "unknown" ]]; then
    echo "An existing install was found in ${INSTALL_DIR}."
    if (( FORCE_MODE )) || prompt_confirm "Replace it with v${newv}?" "N"; then
      return 0
    fi
    exit 1
  fi

  if [[ "${inst}" == "${newv}" ]]; then
    echo "You already have ${APP_NAME} v${inst} installed in ${INSTALL_DIR}."
    if (( FORCE_MODE )); then
      echo "Reinstalling the same version (--force)."
      return 0
    fi
    if (( ! INTERACTIVE )); then
      die "the same version is already installed; pass --force to reinstall"
    fi
    if prompt_confirm "You already have this version. Update/reinstall it anyway?" "N"; then
      return 0
    fi
    exit 1
  fi

  if version_newer "${newv}" "${inst}"; then
    if (( FORCE_MODE )) || prompt_confirm "Update available: v${inst} -> v${newv}. Update now?" "Y"; then
      return 0
    fi
    exit 1
  fi

  echo "Note: installed v${inst} is newer than the bundle v${newv}."
  if (( FORCE_MODE )) || prompt_confirm "Downgrade anyway?" "N"; then
    return 0
  fi
  exit 1
}

# --- uninstall --------------------------------------------------------------------

uninstall() {
  if pgrep -x "${BINARY_NAME}" >/dev/null 2>&1; then
    die "${APP_NAME} is running. Close it before uninstalling."
  fi
  setup_privileges

  local launcher desktop_file
  launcher="$([[ -n "${SUDO}" ]] && echo "/usr/local/bin/zephyr" || echo "${HOME}/.local/bin/zephyr")"
  desktop_file="$([[ -n "${SUDO}" ]] && echo "/usr/share/applications/${APP_ID}.desktop" || echo "${XDG_DATA_HOME:-${HOME}/.local/share}/applications/${APP_ID}.desktop")"

  run rm -rf -- "${INSTALL_DIR}"
  run rm -f -- "${launcher}" "${desktop_file}"
  if command -v update-desktop-database >/dev/null 2>&1; then
    local apps_dir
    apps_dir="$(dirname -- "${desktop_file}")"
    run update-desktop-database "${apps_dir}" >/dev/null 2>&1 || true
  fi
  echo "Removed ${APP_NAME} from ${INSTALL_DIR}"
}

# --- install -------------------------------------------------------------------------

install() {
  local launcher desktop_file apps_dir

  if pgrep -x "${BINARY_NAME}" >/dev/null 2>&1; then
    die "${APP_NAME} is running. Close it before installing an update."
  fi

  # Version/channel known early (pubspec fallback) so we can build if needed
  NEW_VERSION="$(new_version)"
  NEW_CHANNEL="$(new_channel)"

  # Maybe build from a source checkout when no bundle exists yet
  if [[ -z "${BUNDLE_DIR}" && -x "$(command -v flutter)" && -f "${APP_ROOT}/pubspec.yaml" ]]; then
    echo "No bundle found; building ${APP_NAME} (${NEW_CHANNEL}) with Flutter..."
    (cd -- "${APP_ROOT}" && flutter build linux --release --dart-define="RELEASE_CHANNEL=${NEW_CHANNEL}")
    BUNDLE_DIR="${DEFAULT_BUNDLE}"
  fi
  locate_bundle
  [[ -x "${BUNDLE_DIR}/${BINARY_NAME}" ]] || die "missing binary: ${BUNDLE_DIR}/${BINARY_NAME}"

  # A distributed bundle may ship its own VERSION marker - prefer it
  NEW_VERSION="$(new_version)"
  NEW_CHANNEL="$(new_channel)"
  DISPLAY_VERSION="v${NEW_VERSION} ${NEW_CHANNEL}"

  select_install_dir

  echo
  echo "Installing ${APP_NAME} ${DISPLAY_VERSION}"
  echo "  bundle:      ${BUNDLE_DIR}"
  echo "  destination: ${INSTALL_DIR}"
  echo

  confirm_before_install
  setup_privileges

  if [[ -n "${SUDO}" ]]; then
    launcher="/usr/local/bin/zephyr"
    apps_dir="/usr/share/applications"
  else
    launcher="${HOME}/.local/bin/zephyr"
    apps_dir="${XDG_DATA_HOME:-${HOME}/.local/share}/applications"
  fi
  desktop_file="${apps_dir}/${APP_ID}.desktop"

  temp_dir=""
cleanup() { rm -rf -- "${temp_dir}"; }

trap cleanup EXIT

if [[ -n "${SUDO}" ]]; then
    temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/zephyr-install.XXXXXX")"
  else
    mkdir -p -- "$(dirname -- "${INSTALL_DIR}")"
    temp_dir="$(mktemp -d "$(dirname -- "${INSTALL_DIR}")/.zephyr-install.XXXXXX")"
  fi

cp -a -- "${BUNDLE_DIR}/." "${temp_dir}/"
  chmod +x -- "${temp_dir}/${BINARY_NAME}"

  # remember the version/channel for future update checks
  printf '%s %s\n' "${NEW_VERSION}" "${NEW_CHANNEL}" > "${temp_dir}/${META_FILE}"

  run rm -rf -- "${INSTALL_DIR}"
  run mkdir -p -- "$(dirname -- "${INSTALL_DIR}")"
  run mv -- "${temp_dir}" "${INSTALL_DIR}"
  trap - EXIT

  run mkdir -p -- "$(dirname -- "${launcher}")"
  run ln -sfn -- "${INSTALL_DIR}/${BINARY_NAME}" "${launcher}"

  run mkdir -p -- "${apps_dir}"
  run tee "${desktop_file}" >/dev/null <<EOF
[Desktop Entry]
Type=Application
Name=${APP_NAME}
Comment=Music streaming client ${DISPLAY_VERSION}
Exec=${INSTALL_DIR}/${BINARY_NAME} %U
Icon=${INSTALL_DIR}/data/flutter_assets/References/Zephyr.png
Terminal=false
Categories=AudioVideo;Audio;Player;
StartupWMClass=${APP_ID}
X-GNOME-UsesNotifications=true
EOF

  if command -v update-desktop-database >/dev/null 2>&1; then
    run update-desktop-database "${apps_dir}" >/dev/null 2>&1 || true
  fi

  cat <<EOF

Installed ${APP_NAME} (${DISPLAY_VERSION})
Application: ${INSTALL_DIR}/${BINARY_NAME}
Launcher:    ${launcher}
Menu entry:  ${desktop_file}

Start it with:
  ${launcher}
EOF
}

# --- main ----------------------------------------------------------------------------

if (( UNINSTALL_MODE )); then
  uninstall
  exit 0
fi

install