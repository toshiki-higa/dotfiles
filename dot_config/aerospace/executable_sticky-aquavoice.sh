#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE_ID="com.electron.aqua-voice"
TARGET_WS="${AEROSPACE_FOCUSED_WORKSPACE:-}"
[[ -z "${TARGET_WS}" ]] && exit 0

WINDOW_IDS="$(aerospace list-windows --monitor all --app-bundle-id "${APP_BUNDLE_ID}" --format '%{window-id}' || true)"
[[ -z "${WINDOW_IDS}" ]] && exit 0

for wid in ${WINDOW_IDS}; do
  aerospace layout --window-id "${wid}" floating >/dev/null 2>&1 || true
  aerospace move-node-to-workspace --window-id "${wid}" "${TARGET_WS}" >/dev/null 2>&1 || true
done
