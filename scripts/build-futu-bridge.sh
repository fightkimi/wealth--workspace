#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$PROJECT_DIR/.build/futu-bridge"
VENV_DIR="$BUILD_ROOT/venv"
DIST_DIR="$BUILD_ROOT/dist"
WORK_DIR="$BUILD_ROOT/work"
SPEC_DIR="$BUILD_ROOT/spec"
PYINSTALLER_CONFIG_DIR="$BUILD_ROOT/pyinstaller-config"

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  python3 -m venv "$VENV_DIR"
fi

"$VENV_DIR/bin/python" -m pip install --disable-pip-version-check \
  -r "$PROJECT_DIR/Resources/requirements-futu.txt"

env PYINSTALLER_CONFIG_DIR="$PYINSTALLER_CONFIG_DIR" \
  "$VENV_DIR/bin/pyinstaller" \
  --noconfirm \
  --clean \
  --onedir \
  --name futu_bridge \
  --distpath "$DIST_DIR" \
  --workpath "$WORK_DIR" \
  --specpath "$SPEC_DIR" \
  --collect-data futu \
  "$PROJECT_DIR/Resources/futu_bridge.py"

rm -rf "$PROJECT_DIR/Resources/Tools/futu_bridge"
cp -R "$DIST_DIR/futu_bridge" "$PROJECT_DIR/Resources/Tools/futu_bridge"
chmod 755 "$PROJECT_DIR/Resources/Tools/futu_bridge/futu_bridge"
