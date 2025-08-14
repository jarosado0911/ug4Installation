#!/usr/bin/env bash
# ug4_install.sh — clone the UG4 "ughub" repository locally and create a sibling "ug4" folder
#
# Usage:
#   ./ug4_install.sh [target_dir]
# Examples:
#   ./ug4_install.sh                   # clones into ./ughub and creates ./ug4
#   ./ug4_install.sh ~/src/ughub       # clones into ~/src/ughub and creates ~/src/ug4
#
# Optional env vars:
#   USE_SSH=1            # use SSH instead of HTTPS
#   CLONE_DEPTH=1        # shallow clone (omit or unset for full history)
#   UGHUB_REPO_URL=...   # override repo URL (defaults to UG4/ughub)
#   UGHUB_BRANCH=main    # branch to checkout (defaults to default branch)

set -euo pipefail

# Choose URL (HTTPS by default; SSH if requested)
if [[ "${USE_SSH:-0}" == "1" ]]; then
  REPO_URL="${UGHUB_REPO_URL:-git@github.com:UG4/ughub.git}"
else
  REPO_URL="${UGHUB_REPO_URL:-https://github.com/UG4/ughub.git}"
fi

TARGET_DIR="${1:-ughub}"
BRANCH_OPT=()
if [[ -n "${UGHUB_BRANCH:-}" ]]; then
  BRANCH_OPT=(--branch "$UGHUB_BRANCH")
fi

# Check for git
if ! command -v git >/dev/null 2>&1; then
  echo "Error: git is not installed or not on PATH." >&2
  exit 1
fi

# Prevent accidental overwrite of clone target
if [[ -e "$TARGET_DIR" ]]; then
  echo "Error: target path '$TARGET_DIR' already exists. Choose another directory." >&2
  exit 1
fi

# Clone ughub
CLONE_ARGS=()
if [[ -n "${CLONE_DEPTH:-}" ]]; then
  CLONE_ARGS+=(--depth "$CLONE_DEPTH")
fi

echo "Cloning ughub from: $REPO_URL"
echo "Into directory:      $TARGET_DIR"
[[ ${#BRANCH_OPT[@]} -gt 0 ]] && echo "Branch:              ${UGHUB_BRANCH}"

git clone "${CLONE_ARGS[@]}" "${BRANCH_OPT[@]}" "$REPO_URL" "$TARGET_DIR"

echo "Done. Remotes:"
git -C "$TARGET_DIR" remote -v

# --- Create sibling 'ug4' directory next to 'ughub' ---
UG4_PARENT_DIR="$(dirname "$TARGET_DIR")"
# If TARGET_DIR has no slash, dirname returns '.', which is fine
UG4_DIR="${UG4_PARENT_DIR%/}/ug4"

# If UG4_PARENT_DIR is '.', make path './ug4' explicitly (cosmetic)
if [[ "$UG4_PARENT_DIR" == "." ]]; then
  UG4_DIR="./ug4"
fi

if [[ -e "$UG4_DIR" && ! -d "$UG4_DIR" ]]; then
  echo "Error: '$UG4_DIR' exists but is not a directory." >&2
  exit 1
fi

mkdir -p "$UG4_DIR"
echo "Created sibling directory: $UG4_DIR"
