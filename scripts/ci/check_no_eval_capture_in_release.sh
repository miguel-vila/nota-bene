#!/usr/bin/env bash
# Asserts that the EVAL_CAPTURE compilation condition is gated on the Debug
# build configuration in Package.swift and is never unconditionally defined.
# Catches both:
#   1. Someone replacing `.define("EVAL_CAPTURE", .when(configuration: .debug))`
#      with a bare `.define("EVAL_CAPTURE")` (would ship in Release).
#   2. Someone adding `.when(configuration: .release)` (would ship in Release).
#
# Wire as a required step before any release-archive job — see
# .github/workflows/ci.yml.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PKG="${REPO_ROOT}/Package.swift"

if [ ! -f "${PKG}" ]; then
  echo "[check_no_eval_capture_in_release] Package.swift not found at ${PKG}"
  exit 1
fi

# 1. EVAL_CAPTURE must be defined exactly once, with a .when(configuration: .debug) guard.
EXPECTED='.define("EVAL_CAPTURE", .when(configuration: .debug))'
if ! grep -F -- "${EXPECTED}" "${PKG}" >/dev/null; then
  echo "FAIL: expected the exact form in Package.swift:"
  echo "      ${EXPECTED}"
  echo "      Current EVAL_CAPTURE-related lines:"
  grep -n "EVAL_CAPTURE" "${PKG}" || echo "      (none)"
  exit 1
fi

# 2. No other EVAL_CAPTURE define forms allowed.
DEFINE_COUNT=$(grep -c '\.define("EVAL_CAPTURE"' "${PKG}" || true)
if [ "${DEFINE_COUNT}" != "1" ]; then
  echo "FAIL: Package.swift has ${DEFINE_COUNT} .define(\"EVAL_CAPTURE\" …) entries; expected exactly 1."
  grep -n 'EVAL_CAPTURE' "${PKG}"
  exit 1
fi

# 3. Nothing should mention .release configuration for EVAL_CAPTURE.
if grep -E 'EVAL_CAPTURE.*\.release|\.release.*EVAL_CAPTURE' "${PKG}" >/dev/null; then
  echo "FAIL: Package.swift mentions .release configuration for EVAL_CAPTURE."
  grep -n 'EVAL_CAPTURE' "${PKG}"
  exit 1
fi

echo "[check_no_eval_capture_in_release] OK — Package.swift gates EVAL_CAPTURE to Debug only."
