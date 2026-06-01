#!/usr/bin/env bash
# Fails the build if the EVAL_CAPTURE compilation condition is ever present in
# the Release configuration. EVAL_CAPTURE gates the on-device eval-sample
# writer (see docs/eval-capture.md) and must never ship outside DEBUG builds.
#
# Wire as a required step before any release-archive job.
set -euo pipefail

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "[check_no_eval_capture_in_release] xcodebuild not found — skipping (non-mac CI?)"
  exit 0
fi

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if [ ! -f "${REPO_ROOT}/NotaBene.xcodeproj/project.pbxproj" ]; then
  if [ ! -f "${REPO_ROOT}/ReadwiseHighlighter.xcodeproj/project.pbxproj" ]; then
    echo "[check_no_eval_capture_in_release] no .xcodeproj found at repo root — run 'xcodegen generate' first"
    exit 1
  fi
fi

cd "${REPO_ROOT}"

PROJECT_FLAG=""
if [ -d "NotaBene.xcodeproj" ]; then
  PROJECT_FLAG="-project NotaBene.xcodeproj"
elif [ -d "ReadwiseHighlighter.xcodeproj" ]; then
  PROJECT_FLAG="-project ReadwiseHighlighter.xcodeproj"
fi

# shellcheck disable=SC2086
SETTINGS=$(xcodebuild ${PROJECT_FLAG} -configuration Release -showBuildSettings 2>/dev/null || true)

if echo "${SETTINGS}" | grep -E "SWIFT_ACTIVE_COMPILATION_CONDITIONS\s*=.*EVAL_CAPTURE" >/dev/null; then
  echo ""
  echo "FAIL: EVAL_CAPTURE found in SWIFT_ACTIVE_COMPILATION_CONDITIONS for Release config."
  echo "      This flag must only be defined for the Debug configuration."
  echo "      See project.yml and docs/eval-capture.md."
  echo ""
  echo "${SETTINGS}" | grep "SWIFT_ACTIVE_COMPILATION_CONDITIONS" || true
  exit 1
fi

echo "[check_no_eval_capture_in_release] OK — EVAL_CAPTURE not present in Release build."
