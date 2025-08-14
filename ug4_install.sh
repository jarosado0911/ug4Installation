#!/usr/bin/env bash
# ug4_install.sh — clone UG4 "ughub", create sibling "ug4", init ug4 via ../ughub/ughub,
#                   then configure a Debug build (re-adding BLAS/LAPACK paths if CMake can't find them).
#
# Usage:
#   ./ug4_install.sh [target_dir]
# Examples:
#   ./ug4_install.sh                 # clones into ./ughub, creates ./ug4, inits & cmake config
#   ./ug4_install.sh ~/src/ughub     # clones into ~/src/ughub and creates ~/src/ug4
#
# Optional env vars:
#   USE_SSH=1                    # use SSH instead of HTTPS
#   CLONE_DEPTH=1                # shallow clone
#   UGHUB_REPO_URL=...           # override repo URL (default UG4/ughub)
#   UGHUB_BRANCH=main            # branch to checkout (defaults to default branch)
#   LAPACK_LIB_OVERRIDE=...      # override LAPACK .so path for fallback cmake
#   BLAS_LIB_OVERRIDE=...        # override BLAS .so path for fallback cmake

set -euo pipefail

# ---- Helpers ---------------------------------------------------------------
msg() { printf '%s\n' "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
abspath() {
  case "${1:-}" in
    /*) printf '%s\n' "$1" ;;
    *)  local d; d="$(cd "$(dirname "$1")" >/dev/null 2>&1 && pwd -P)"
        printf '%s/%s\n' "$d" "$(basename "$1")"
        ;;
  esac
}

# ---- Config ----------------------------------------------------------------
if [[ "${USE_SSH:-0}" == "1" ]]; then
  REPO_URL="${UGHUB_REPO_URL:-git@github.com:UG4/ughub.git}"
else
  REPO_URL="${UGHUB_REPO_URL:-https://github.com/UG4/ughub.git}"
fi

TARGET_DIR="${1:-ughub}"             # clone destination for the ughub repo (default: ./ughub)
BRANCH_OPT=()
[[ -n "${UGHUB_BRANCH:-}" ]] && BRANCH_OPT=(--branch "$UGHUB_BRANCH")

CLONE_ARGS=()
[[ -n "${CLONE_DEPTH:-}" ]] && CLONE_ARGS+=(--depth "$CLONE_DEPTH")

# ---- Part 1/4: Clone the 'ughub' repository --------------------------------
msg "Part 1/4: Cloning 'ughub' repository"
msg "  Working directory:          $(abspath ".")"
msg "  Repository URL:             $REPO_URL"
msg "  Target clone directory:     $(abspath "$TARGET_DIR")"
[[ ${#BRANCH_OPT[@]} -gt 0 ]] && msg "  Branch:                      ${UGHUB_BRANCH}"
[[ -n "${CLONE_DEPTH:-}" ]] && msg "  Shallow clone depth:         ${CLONE_DEPTH}"

command -v git >/dev/null 2>&1 || { msg "ERROR: git is not installed."; exit 1; }
[[ ! -e "$TARGET_DIR" ]] || { msg "ERROR: '$TARGET_DIR' already exists."; exit 1; }

msg "-> Running: git clone ${CLONE_ARGS[*]:-} ${BRANCH_OPT[*]:-} \"$REPO_URL\" \"$TARGET_DIR\""
git clone "${CLONE_ARGS[@]}" "${BRANCH_OPT[@]}" "$REPO_URL" "$TARGET_DIR"
msg "Clone complete."
git -C "$TARGET_DIR" remote -v

# ---- Part 2/4: Create sibling 'ug4' directory ------------------------------
UG4_PARENT_DIR="$(dirname "$TARGET_DIR")"
UG4_DIR="${UG4_PARENT_DIR%/}/ug4"
[[ "$UG4_PARENT_DIR" == "." ]] && UG4_DIR="./ug4"

msg "Part 2/4: Creating sibling 'ug4' directory"
msg "  Parent directory (of ughub): $(abspath "$UG4_PARENT_DIR")"
msg "  ug4 directory to create:     $(abspath "$UG4_DIR")"

if [[ -e "$UG4_DIR" && ! -d "$UG4_DIR" ]]; then
  msg "ERROR: '$UG4_DIR' exists but is not a directory."
  exit 1
fi
mkdir -p "$UG4_DIR"
msg "Created (or already existed):  $(abspath "$UG4_DIR")"

# Ensure ../ughub/ughub exists from inside ug4:
# If user chose a different clone name, create a symlink named 'ughub' -> <actual clone dir>
if [[ "$(basename "$TARGET_DIR")" != "ughub" ]]; then
  ( cd "$UG4_PARENT_DIR"
    if [[ -e "ughub" && ! -L "ughub" && ! -d "ughub" ]]; then
      msg "ERROR: '$UG4_PARENT_DIR/ughub' exists and is not a directory/symlink."
      exit 1
    fi
    if [[ ! -e "ughub" ]]; then
      ln -s "$(basename "$TARGET_DIR")" "ughub"
      msg "Created symlink: $(abspath "$UG4_PARENT_DIR")/ughub -> $(basename "$TARGET_DIR")"
    fi
  )
fi

# ---- Part 3/4: Initialize ug4 via ../ughub/ughub ---------------------------
REL_UGHUB="../ughub/ughub"
msg "Part 3/4: Initializing ug4 using relative path"
msg "  Changing directory to:       $(abspath "$UG4_DIR")"
pushd "$UG4_DIR" >/dev/null

# Prefer executing ../ughub/ughub directly; fall back to python3 if not executable
if [[ -x "$REL_UGHUB" ]]; then
  UGHUB_CMD=( "$REL_UGHUB" )
elif command -v python3 >/dev/null 2>&1; then
  UGHUB_CMD=( python3 "$REL_UGHUB" )
else
  msg "ERROR: '$REL_UGHUB' is not executable and 'python3' not found."
  exit 1
fi

msg "-> Running: ${UGHUB_CMD[*]} init"
"${UGHUB_CMD[@]}" init

msg "-> Running: ${UGHUB_CMD[*]} install Examples"
"${UGHUB_CMD[@]}" install Examples

# ---- Part 4/4: Configure CMake build in ug4/build --------------------------
BUILD_DIR="build"
msg "Part 4/4: Configuring CMake"
msg "  Build directory:             $(abspath "$UG4_DIR/$BUILD_DIR")"

mkdir -p "$BUILD_DIR"
pushd "$BUILD_DIR" >/dev/null

# Base CMake args
BASE_ARGS=(-DPARALLEL=OFF -DCMAKE_BUILD_TYPE=Debug -DConvectionDiffusion=ON ..)

# First attempt: no explicit BLAS/LAPACK
msg "-> Running: cmake ${BASE_ARGS[*]}"
set +e
cmake "${BASE_ARGS[@]}" 2>&1 | tee cmake_first.log
CMAKE_RC=${PIPESTATUS[0]}
set -e

# Detect BLAS/LAPACK problems in output or non-zero rc
if [[ $CMAKE_RC -ne 0 ]] || grep -Eq 'A library with BLAS API not found|No LAPACK package found|LAPACK requires BLAS' cmake_first.log; then
  LAPACK_LIB="${LAPACK_LIB_OVERRIDE:-/usr/lib/x86_64-linux-gnu/lapack/liblapack.so}"
  BLAS_LIB="${BLAS_LIB_OVERRIDE:-/usr/lib/x86_64-linux-gnu/libblas.so}"

  msg "CMake reported missing BLAS/LAPACK or failed. Retrying with explicit libraries:"
  msg "  LAPACK: $LAPACK_LIB"
  msg "  BLAS:   $BLAS_LIB"

  # Second attempt with explicit libs
  msg "-> Running: cmake ${BASE_ARGS[*]} -DUSER_LAPACK_LIBRARIES=\"$LAPACK_LIB\" -DUSER_BLAS_LIBRARIES=\"$BLAS_LIB\""
  set +e
  cmake "${BASE_ARGS[@]}" \
        -DUSER_LAPACK_LIBRARIES="$LAPACK_LIB" \
        -DUSER_BLAS_LIBRARIES="$BLAS_LIB" 2>&1 | tee cmake_with_blas_lapack.log
  CMAKE_RC2=${PIPESTATUS[0]}
  set -e

  if [[ $CMAKE_RC2 -ne 0 ]]; then
    msg "ERROR: CMake configuration still failed. See logs:"
    msg "  $(abspath cmake_first.log)"
    msg "  $(abspath cmake_with_blas_lapack.log)"
    exit 1
  else
    msg "CMake configuration succeeded with explicit BLAS/LAPACK."
  fi
else
  msg "CMake configuration succeeded on first attempt."
fi

popd >/dev/null   # leave build/
popd >/dev/null   # leave ug4/
msg "All done. ug4 initialized and CMake configured."
