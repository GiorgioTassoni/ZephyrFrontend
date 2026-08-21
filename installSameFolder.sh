#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="Zephyr Music Client"
APP_ID="com.giorgiotassoni.zephyr"
BINARY_NAME="frontend"
RELEASE_CHANNEL="${RELEASE_CHANNEL:-Preview}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="${SCRIPT_DIR}/apps/zephyr_desktop"
DEFAULT_BUNDLE="${APP_ROOT}/build/linux/x64/release/bundle"
INSTALL_DIR="${ZEPHYR_INSTALL_DIR:-${HOME}/.local/opt/zephyr}"
BIN_DIR="${HOME}/.local/bin"
APPLICATIONS_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/applications"
DESKTOP_FILE="${APPLICATIONS_DIR}/${APP_ID}.desktop"
LAUNCHER="${BIN_DIR}/zephyr"

usage() {
  cat <<'EOF'
Usage:
  ./installSameFolder.sh
  ./installSameFolder.sh --uninstall

The script expects either:
  1. A bundle/ directory beside this script,
  2. frontend, data/, and lib/ beside this script, or
  3. A freshly built Flutter bundle at
     apps/zephyr_desktop/build/linux/x64/release/bundle.

The bundle is installed to ~/.local/opt/zephyr. Set ZEPHYR_INSTALL_DIR to
choose a different user-local installation directory.
EOF
}

uninstall() {
  if pgrep -x "${BINARY_NAME}" >/dev/null 2>&1; then
    echo "Zephyr is running. Close it before uninstalling." >&2
    exit 1
  fi

  rm -rf -- "${INSTALL_DIR}"
  rm -f -- "${LAUNCHER}" "${DESKTOP_FILE}"
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${APPLICATIONS_DIR}" >/dev/null 2>&1 || true
  fi
  echo "Removed ${APP_NAME} from ${INSTALL_DIR}"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "--uninstall" ]]; then
  uninstall
  exit 0
fi

if [[ "${#}" -ne 0 ]]; then
  usage >&2
  exit 2
fi

if [[ -x "${SCRIPT_DIR}/bundle/${BINARY_NAME}" ]]; then
  BUNDLE_DIR="${SCRIPT_DIR}/bundle"
elif [[ -x "${SCRIPT_DIR}/${BINARY_NAME}" ]]; then
  BUNDLE_DIR="${SCRIPT_DIR}"
elif [[ -x "${DEFAULT_BUNDLE}/${BINARY_NAME}" ]]; then
  BUNDLE_DIR="${DEFAULT_BUNDLE}"
else
  echo "Could not find a Linux bundle beside ${BASH_SOURCE[0]}." >&2
  echo "Expected bundle/frontend or frontend beside the installer, or a built" >&2
  echo "bundle at ${DEFAULT_BUNDLE}." >&2
  exit 1
fi

BINARY_PATH="${BUNDLE_DIR}/${BINARY_NAME}"
if [[ ! -d "${BUNDLE_DIR}/data" || ! -d "${BUNDLE_DIR}/lib" ]]; then
  echo "Incomplete Flutter Linux bundle: ${BUNDLE_DIR}" >&2
  echo "The bundle must contain frontend, data/, and lib/." >&2
  exit 1
fi

if pgrep -x "${BINARY_NAME}" >/dev/null 2>&1; then
  echo "${APP_NAME} is running. Close it before installing an update." >&2
  exit 1
fi

APP_VERSION="unknown"
if [[ -f "${APP_ROOT}/pubspec.yaml" ]]; then
  APP_VERSION="$(sed -n 's/^version:[[:space:]]*\([^+[:space:]]*\).*/\1/p' "${APP_ROOT}/pubspec.yaml" | head -n 1 || true)"
  APP_VERSION="${APP_VERSION:-unknown}"
fi
DISPLAY_VERSION="v${APP_VERSION} ${RELEASE_CHANNEL}"

mkdir -p -- "$(dirname -- "${INSTALL_DIR}")" "${BIN_DIR}" "${APPLICATIONS_DIR}"
TEMP_DIR="$(mktemp -d "$(dirname -- "${INSTALL_DIR}")/.zephyr-install.XXXXXX")"
cleanup() {
  rm -rf -- "${TEMP_DIR}"
}
trap cleanup EXIT

cp -a -- "${BUNDLE_DIR}/." "${TEMP_DIR}/"
chmod +x -- "${TEMP_DIR}/${BINARY_NAME}"

rm -rf -- "${INSTALL_DIR}"
mv -- "${TEMP_DIR}" "${INSTALL_DIR}"
trap - EXIT

ln -sfn -- "${INSTALL_DIR}/${BINARY_NAME}" "${LAUNCHER}"

cat > "${DESKTOP_FILE}" <<EOF
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
  update-desktop-database "${APPLICATIONS_DIR}" >/dev/null 2>&1 || true
fi

cat <<EOF
Installed ${APP_NAME} (${DISPLAY_VERSION})
Application: ${INSTALL_DIR}/${BINARY_NAME}
Launcher:    ${LAUNCHER}
Menu entry:  ${DESKTOP_FILE}

Start it with:
  ${LAUNCHER}
EOF
