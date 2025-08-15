#!/usr/bin/env bash
# ug4_install.sh — clone UG4 "ughub", create sibling "ug4", init via ../ughub/ughub,
#                  then configure CMake in ug4/build.
# Flags:
#   -mpi       → try mpicc/mpicxx, set -DPARALLEL=ON (fallback to gcc/g++)
#   -promesh   → add -DProMesh=ON to CMake
#   -neuro     → add NeuroBox source, install packages, enable neuro CMake flags
#   -lu        → install SuperLU6 plugin and clone upstream SuperLU into external/superlu
#
# Usage:
#   ./ug4_install.sh [-mpi] [-promesh] [-neuro] [-lu] [target_dir]
#
# Optional env vars:
#   USE_SSH=1                    # use SSH instead of HTTPS for cloning
#   CLONE_DEPTH=1                # shallow clone
#   UGHUB_REPO_URL=...           # override repo URL (default UG4/ughub)
#   UGHUB_BRANCH=main            # branch to checkout (defaults to repo default)
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
find_tool() {
  if command -v "$1" >/dev/null 2>&1; then
    command -v "$1"
  else
    printf ''
  fi
}

# ---- Args ------------------------------------------------------------------
MPI_MODE=0
PROMESH_MODE=0
NEURO_MODE=0
LU_MODE=0
TARGET_DIR=''

while [[ $# -gt 0 ]]; do
  case "$1" in
    -mpi)     MPI_MODE=1; shift ;;
    -promesh) PROMESH_MODE=1; shift ;;
    -neuro)   NEURO_MODE=1; shift ;;
    -lu)      LU_MODE=1; shift ;;
    -h|--help)
      sed -n '1,140p' "$0"; exit 0 ;;
    -*)
      msg "Unknown option: $1"; exit 2 ;;
    *)
      TARGET_DIR="$1"; shift ;;
  esac
done
TARGET_DIR="${TARGET_DIR:-ughub}"

# ---- Config ----------------------------------------------------------------
if [[ "${USE_SSH:-0}" == "1" ]]; then
  REPO_URL="${UGHUB_REPO_URL:-git@github.com:UG4/ughub.git}"
else
  REPO_URL="${UGHUB_REPO_URL:-https://github.com/UG4/ughub.git}"
fi
BRANCH_OPT=()
[[ -n "${UGHUB_BRANCH:-}" ]] && BRANCH_OPT=(--branch "$UGHUB_BRANCH")
CLONE_ARGS=()
[[ -n "${CLONE_DEPTH:-}" ]] && CLONE_ARGS+=(--depth "$CLONE_DEPTH")

# ---- Part 1/8: Clone the 'ughub' repository --------------------------------
msg "Part 1/8: Cloning 'ughub' repository"
msg "  Working directory:          $(abspath ".")"
msg "  Repository URL:             $REPO_URL"
msg "  Target clone directory:     $(abspath "$TARGET_DIR")"
[[ ${#BRANCH_OPT[@]} -gt 0 ]] && msg "  Branch:                      ${UGHUB_BRANCH:-<repo default>}"
[[ -n "${CLONE_DEPTH:-}" ]] && msg "  Shallow clone depth:         ${CLONE_DEPTH}"

command -v git >/dev/null 2>&1 || { msg "ERROR: git is not installed."; exit 1; }
[[ ! -e "$TARGET_DIR" ]] || { msg "ERROR: '$TARGET_DIR' already exists."; exit 1; }

msg "-> Running: git clone ${CLONE_ARGS[*]:-} ${BRANCH_OPT[*]:-} \"$REPO_URL\" \"$TARGET_DIR\""
git clone "${CLONE_ARGS[@]}" "${BRANCH_OPT[@]}" "$REPO_URL" "$TARGET_DIR"
msg "Clone complete."
git -C "$TARGET_DIR" remote -v

# ---- Part 2/8: Create sibling 'ug4' directory ------------------------------
UG4_PARENT_DIR="$(dirname "$TARGET_DIR")"
UG4_DIR="${UG4_PARENT_DIR%/}/ug4"
[[ "$UG4_PARENT_DIR" == "." ]] && UG4_DIR="./ug4"

msg "Part 2/8: Creating sibling 'ug4' directory"
msg "  Parent directory (of ughub): $(abspath "$UG4_PARENT_DIR")"
msg "  ug4 directory to create:     $(abspath "$UG4_DIR")"

if [[ -e "$UG4_DIR" && ! -d "$UG4_DIR" ]]; then
  msg "ERROR: '$UG4_DIR' exists but is not a directory."
  exit 1
fi
mkdir -p "$UG4_DIR"
msg "Created (or already existed):  $(abspath "$UG4_DIR")"

# Ensure ../ughub/ughub resolves even if clone dir isn't named "ughub"
if [[ "$(basename "$TARGET_DIR")" != "ughub" ]]; then
  (
    cd "$UG4_PARENT_DIR"
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

# ---- Part 3/8: Initialize ug4 via ../ughub/ughub ---------------------------
REL_UGHUB="../ughub/ughub"
msg "Part 3/8: Initializing ug4 using relative path"
msg "  Changing directory to:       $(abspath "$UG4_DIR")"
pushd "$UG4_DIR" >/dev/null

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

# ---- Part 4/8: NeuroBox (handles -neuro) -----------------------------------
if [[ $NEURO_MODE -eq 1 ]]; then
  msg "Neuro mode enabled (-neuro): adding NeuroBox source and installing packages."
  msg "-> Running: ${UGHUB_CMD[*]} addsource neurobox https://github.com/NeuroBox3D/neurobox-packages.git"
  "${UGHUB_CMD[@]}" addsource neurobox https://github.com/NeuroBox3D/neurobox-packages.git

  msg "-> Running: ${UGHUB_CMD[*]} install neuro_collection cable_neuron MembranePotentialMapping"
  "${UGHUB_CMD[@]}" install neuro_collection cable_neuron MembranePotentialMapping
fi

# ---- Part 5/8: SuperLU6 (handles -lu) --------------------------------------
if [[ $LU_MODE -eq 1 ]]; then
  msg "SuperLU mode enabled (-lu): installing SuperLU6 and wiring external source."
  msg "-> Running: ${UGHUB_CMD[*]} install SuperLU6"
  "${UGHUB_CMD[@]}" install SuperLU6

  EXTERNAL_DIR="plugins/SuperLU6/external"
  msg "  Preparing external directory: $(abspath "$EXTERNAL_DIR")"
  mkdir -p "$EXTERNAL_DIR"
  pushd "$EXTERNAL_DIR" >/dev/null

  if [[ -e superlu ]]; then
    msg "  Removing existing 'superlu' at: $(abspath superlu)"
    rm -rf superlu
  fi

  msg "  Cloning upstream SuperLU into 'superlu'..."
  git clone https://github.com/xiaoyeli/superlu.git superlu
  msg "  SuperLU ready at: $(abspath superlu)"
  popd >/dev/null
fi

# ---- Part 6/8: Select compilers (handles -mpi) -----------------------------
PARALLEL_VAL="OFF"
C_COMP=""
CXX_COMP=""

if [[ $MPI_MODE -eq 1 ]]; then
  PARALLEL_VAL="ON"
  msg "MPI mode requested (-mpi). Searching for MPI compilers..."

  MPICC_PATH="$(find_tool mpicc || true)"
  MPICXX_PATH="$(find_tool mpicxx || true)"
  [[ -z "$MPICC_PATH" && -x /usr/bin/mpicc ]] && MPICC_PATH="/usr/bin/mpicc"
  [[ -z "$MPICXX_PATH" && -x /usr/bin/mpicxx ]] && MPICXX_PATH="/usr/bin/mpicxx"

  if [[ -n "$MPICC_PATH" && -n "$MPICXX_PATH" ]]; then
    C_COMP="$MPICC_PATH"
    CXX_COMP="$MPICXX_PATH"
    msg "  Found MPI compilers:"
    msg "    mpicc : $C_COMP"
    msg "    mpicxx: $CXX_COMP"
  else
    msg "WARNING: MPI compilers not found. Falling back to non-MPI toolchain."
  fi
fi

if [[ -z "${C_COMP:-}" || -z "${CXX_COMP:-}" ]]; then
  C_COMP="$(find_tool gcc || true)"; CXX_COMP="$(find_tool g++ || true)"
  if [[ -z "$C_COMP" || -z "$CXX_COMP" ]]; then
    C_COMP="$(find_tool cc || true)"; CXX_COMP="$(find_tool c++ || true)"
  fi
  if [[ -z "$C_COMP" || -z "$CXX_COMP" ]]; then
    msg "ERROR: Could not find a C/C++ compiler toolchain (gcc/g++ or cc/c++)."
    exit 1
  fi
  if [[ $MPI_MODE -eq 1 ]]; then
    msg "MPI not available; proceeding without MPI (PARALLEL=OFF)."
    PARALLEL_VAL="OFF"
  fi
  msg "  Using fallback compilers:"
  msg "    C  : $C_COMP"
  msg "    C++: $CXX_COMP"
fi

# ---- Part 7/8: Prepare CMake args (handles -promesh, -neuro) ---------------
BASE_ARGS=(
  -DPARALLEL="${PARALLEL_VAL}"
  -DCMAKE_BUILD_TYPE=Debug
  -DConvectionDiffusion=ON
)
if [[ $PROMESH_MODE -eq 1 ]]; then
  msg "ProMesh enabled (-promesh): adding -DProMesh=ON to CMake."
  BASE_ARGS+=(-DProMesh=ON)
fi
if [[ $NEURO_MODE -eq 1 ]]; then
  msg "Neuro options enabled (-neuro): adding Neuro-related CMake flags."
  BASE_ARGS+=(-Dneuro_collection=ON -Dcable_neuron=ON -DMembranePotentialMapping=ON)
fi
if [[ $LU_MODE     -eq 1 ]]; then
  msg "SuperLU option enabled (-lu): adding SuperLU Cmake flag."
  BASE_ARGS+=(-DSuperLU6=ON)
fi

COMPILER_ARGS=(
  -DCMAKE_C_COMPILER="${C_COMP}"
  -DCMAKE_CXX_COMPILER="${CXX_COMP}"
)

# ---- Part 8/8: Configure CMake build in ug4/build --------------------------
BUILD_DIR="build"
msg "Configuring CMake in:          $(abspath "$UG4_DIR/$BUILD_DIR")"
mkdir -p "$BUILD_DIR"
pushd "$BUILD_DIR" >/dev/null

msg "-> Running: cmake ${COMPILER_ARGS[*]} ${BASE_ARGS[*]} .."
set +e
cmake "${COMPILER_ARGS[@]}" "${BASE_ARGS[@]}" .. 2>&1 | tee cmake_first.log
CMAKE_RC=${PIPESTATUS[0]}
set -e

# Retry if BLAS/LAPACK not found or non-zero rc
if [[ $CMAKE_RC -ne 0 ]] || grep -Eq 'A library with BLAS API not found|No LAPACK package found|LAPACK requires BLAS' cmake_first.log; then
  LAPACK_LIB="${LAPACK_LIB_OVERRIDE:-/usr/lib/x86_64-linux-gnu/lapack/liblapack.so}"
  BLAS_LIB="${BLAS_LIB_OVERRIDE:-/usr/lib/x86_64-linux-gnu/libblas.so}"
  msg "CMake reported missing BLAS/LAPACK or failed. Retrying with explicit libraries:"
  msg "  LAPACK: $LAPACK_LIB"
  msg "  BLAS:   $BLAS_LIB"
  msg "-> Running: cmake ${COMPILER_ARGS[*]} ${BASE_ARGS[*]} -DUSER_LAPACK_LIBRARIES=\"$LAPACK_LIB\" -DUSER_BLAS_LIBRARIES=\"$BLAS_LIB\" .."
  set +e
  cmake "${COMPILER_ARGS[@]}" "${BASE_ARGS[@]}" \
        -DUSER_LAPACK_LIBRARIES="$LAPACK_LIB" \
        -DUSER_BLAS_LIBRARIES="$BLAS_LIB" .. 2>&1 | tee cmake_with_blas_lapack.log
  CMAKE_RC2=${PIPESTATUS[0]}
  set -e
  if [[ $CMAKE_RC2 -ne 0 ]] && [[ $PARALLEL_VAL == "ON" ]]; then
    msg "NOTE: If MPI is enabled and BLAS/LAPACK detection fails, ensure mpi variants of BLAS/LAPACK are installed."
  fi
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
msg "All done. ug4 initialized and CMake configured (PARALLEL=${PARALLEL_VAL}, ProMesh=$([[ $PROMESH_MODE -eq 1 ]] && echo ON || echo OFF), Neuro=$([[ $NEURO_MODE -eq 1 ]] && echo ON || echo OFF), SuperLU=$([[ $LU_MODE -eq 1 ]] && echo ON || echo OFF))."