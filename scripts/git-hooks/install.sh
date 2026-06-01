#!/usr/bin/env bash
# Symlinks every hook in scripts/git-hooks/ into .git/hooks/. Re-running is
# safe (idempotent). Run once after cloning the repo.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SRC_DIR="${REPO_ROOT}/scripts/git-hooks"
DEST_DIR="${REPO_ROOT}/.git/hooks"

mkdir -p "${DEST_DIR}"

for hook in "${SRC_DIR}"/*; do
  name="$(basename "${hook}")"
  # Skip the installer itself and any non-executable helper files.
  if [ "${name}" = "install.sh" ] || [ "${name}" = "README.md" ]; then
    continue
  fi
  chmod +x "${hook}"
  ln -sf "${hook}" "${DEST_DIR}/${name}"
  echo "installed: ${name}"
done

echo "done."
