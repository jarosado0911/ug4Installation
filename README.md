# ug4Installation
* This repo contains directions and codes for installing the ug4 framework.
* I will provide directions for installing on the following systems:
	- Linxu OS
	- Windows
---

# UG4 Installer (`ug4_install.sh`)

This script automates setting up a UG4 workspace using **ughub**, prepares an `ug4/` working directory, initializes packages, and configures a build with CMake. It supports optional flags to enable **MPI**, **ProMesh**, **NeuroBox** packages, and **SuperLU6**.

---

## Table of Contents

- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Usage & Flags](#usage--flags)
- [What the Script Does (Step-by-Step)](#what-the-script-does-step-by-step)
  - [1) Clone `ughub` repository](#1-clone-ughub-repository)
  - [2) Create `ug4/` workspace (sibling to `ughub/`)](#2-create-ug4-workspace-sibling-to-ughub)
  - [3) Initialize `ug4` & install `Examples`](#3-initialize-ug4--install-examples)
  - [4) *(Optional)* NeuroBox: add source & install packages (`-neuro`)](#4-optional-neurobox-add-source--install-packages--neuro)
  - [5) *(Optional)* SuperLU6 plugin & vendor source (`-lu`)](#5-optional-superlu6-plugin--vendor-source--lu)
  - [6) Compiler selection & MPI (`-mpi`)](#6-compiler-selection--mpi--mpi)
  - [7) Assemble CMake options](#7-assemble-cmake-options)
  - [8) Configure with CMake (+ BLAS/LAPACK fallback)](#8-configure-with-cmake--blaslapack-fallback)
- [CMake Options Explained](#cmake-options-explained)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)

---

## Requirements

- **git** (for cloning repositories)
- **cmake** (3.16+ recommended)
- **Build toolchain**: `gcc/g++` (or `cc/c++`), optionally `mpicc/mpicxx` for MPI
- **python3** (only used if `../ughub/ughub` isn’t directly executable)
- (Optional) **BLAS/LAPACK** development libraries (the script auto-retries with explicit library paths if detection fails)

---

## Quick Start

```bash
chmod +x ug4_install.sh
./ug4_install.sh              # default, non-MPI build
./ug4_install.sh -mpi         # try MPI compilers, enable PARALLEL
./ug4_install.sh -promesh     # enable ProMesh in CMake
./ug4_install.sh -neuro       # add NeuroBox source & packages; enable related CMake options
./ug4_install.sh -lu          # install SuperLU6 & vendor upstream SuperLU; enable -DSuperLU6=ON
./ug4_install.sh -parmetis    # unpack Parmetis.tar -> ug4/plugins/Parmetis and enable -DParmetis=ON
```

By default, the script clones `ughub/` into the current directory and creates a sibling `ug4/` directory next to it.

---

## Usage & Flags

```
./ug4_install.sh [-mpi] [-promesh] [-neuro] [-lu] [-parmetis] [target_dir]
```

- `-mpi` — prefer `mpicc/mpicxx`; sets `-DPARALLEL=ON` (falls back to gcc/g++ if MPI not found)
- `-promesh` — adds `-DProMesh=ON` at configure time
- `-neuro` — adds NeuroBox source, installs `neuro_collection`, `cable_neuron`, `MembranePotentialMapping`; enables their CMake options
- `-lu` — installs `SuperLU6`, vendors upstream **SuperLU** into `plugins/SuperLU6/external/superlu`, and adds `-DSuperLU6=ON`
- `target_dir` — destination for the `ughub` clone (default: `./ughub`)
- `-parmetis` — expects **`Parmetis.tar`** in the directory you run the script from; extracts it to **`ug4/plugins/Parmetis/`** and enables **`-DParmetis=ON`** (the script also adds **`-DPCL_DEBUG_BARRIER=ON`** for extra debug barriers). 
---

## What the Script Does (Step-by-Step)

### 1) Clone `ughub` repository
Clones the official `ughub` repo (HTTPS by default, SSH if `USE_SSH=1`) into `target_dir` and shows remotes. It refuses to overwrite an existing path.

### 2) Create `ug4/` workspace (sibling to `ughub/`)
Creates `./ug4` next to the clone. If your clone isn’t literally named `ughub`, the script creates a **symlink** so `../ughub/ughub` still resolves cleanly from within `ug4/`.

### 3) Initialize `ug4` & install `Examples`
Changes into `ug4/`, then runs:

- `../ughub/ughub init`
- `../ughub/ughub install Examples`

If `../ughub/ughub` is not executable, it falls back to `python3 ../ughub/ughub`.

### 4) *(Optional)* NeuroBox: add source & install packages (`-neuro`)
If `-neuro` is passed:
- `../ughub/ughub addsource neurobox https://github.com/NeuroBox3D/neurobox-packages.git`
- `../ughub/ughub install neuro_collection cable_neuron MembranePotentialMapping`

The CMake step later turns on the corresponding packages.

### 5) *(Optional)* SuperLU6 plugin & vendor source (`-lu`)
If `-lu` is passed:
- `../ughub/ughub install SuperLU6`
- Ensures `ug4/plugins/SuperLU6/external/` exists
- Removes any existing `external/superlu` and runs:
  - `git clone https://github.com/xiaoyeli/superlu.git superlu`

The CMake step later enables `-DSuperLU6=ON`.

### 5b) *(Optional)* ParMETIS from tar (`-parmetis`)
If `-parmetis` is passed:
- The script looks for `Parmetis.tar` in the directory you launched the script from, extracts it under `ug4/plugins/Parmetis/`, and normalizes the folder name if needed. 
- The CMake step adds `-DParmetis=ON` (and `-DPCL_DEBUG_BARRIER=ON`).  
- *Note:* This does **not** automatically enable MPI/parallel; combine with `-mpi` if you also want a parallel build.

### 6) Compiler selection & MPI (`-mpi`)
- If `-mpi` is passed, the script tries `mpicc`/`mpicxx` (PATH or `/usr/bin`), prints the paths if found, **and sets `-DPARALLEL=ON`**.
- If MPI is missing, a clear warning is printed and it falls back to `gcc/g++` or `cc/c++`, resetting `PARALLEL=OFF`.

### 7) Assemble CMake options
Creates a base list of options to pass to `cmake`:
- Always sets `-DCMAKE_BUILD_TYPE=Debug -DConvectionDiffusion=ON`
- Sets `-DPARALLEL=ON|OFF` from step 6
- Adds feature flags based on provided script flags:
  - `-DProMesh=ON` (when `-promesh`)
  - `-Dneuro_collection=ON -Dcable_neuron=ON -DMembranePotentialMapping=ON` (when `-neuro`)
  - `-DSuperLU6=ON` (when `-lu`)
- Always passes explicit compilers via `-DCMAKE_C_COMPILER=… -DCMAKE_CXX_COMPILER=…`

### 8) Configure with CMake (+ BLAS/LAPACK fallback)
- Creates `ug4/build/` and runs:
  ```bash
  cmake -DCMAKE_C_COMPILER=<C> -DCMAKE_CXX_COMPILER=<CXX>         -DPARALLEL=… -DCMAKE_BUILD_TYPE=Debug -DConvectionDiffusion=ON [other flags] ..
  ```
- If CMake fails to discover BLAS/LAPACK (or exits non-zero), it **re-runs** CMake adding:
  ```bash
  -DUSER_LAPACK_LIBRARIES=/usr/lib/x86_64-linux-gnu/lapack/liblapack.so   -DUSER_BLAS_LIBRARIES=/usr/lib/x86_64-linux-gnu/libblas.so
  ```
  You can override these with `LAPACK_LIB_OVERRIDE` and `BLAS_LIB_OVERRIDE`.

> Note: The script configures the build; you can compile afterward with `cmake --build . -j` from `ug4/build/`.

---

## CMake Options Explained

- `-DCMAKE_C_COMPILER=…`, `-DCMAKE_CXX_COMPILER=…`  
  Force C/C++ compilers. In MPI mode this points to `mpicc/mpicxx` (if found). Otherwise to `gcc/g++` (or `cc/c++`).

- `-DCMAKE_BUILD_TYPE=Debug`  
  Build with debugging symbols and minimal optimization. Good for development; change to `Release` for optimized binaries.

- `-DPARALLEL=ON|OFF`  
  Toggles UG4’s MPI-enabled parallel build. `ON` compiles parallel communication layers (requires MPI toolchain); `OFF` builds a serial version.

- `-DConvectionDiffusion=ON`  
  Enables the **Convection-Diffusion** plugin/module in UG4 (e.g., PDE solvers for transport/heat-like equations).

- `-DProMesh=ON` *(with `-promesh`)*  
  Enables **ProMesh** (UG4’s mesh processing/GUI tooling) in the build.

- `-Dneuro_collection=ON`, `-Dcable_neuron=ON`, `-DMembranePotentialMapping=ON` *(with `-neuro`)*  
  Enables NeuroBox-related components: the **neuro_collection** package, **cable_neuron** modeling, and **MembranePotentialMapping** tools.

- `-DSuperLU6=ON` *(with `-lu`)*  
  Enables the **SuperLU6** plugin so UG4 can use SuperLU’s sparse direct solvers. The script additionally vendors upstream **superlu** sources under `plugins/SuperLU6/external/superlu`.

- `-DUSER_LAPACK_LIBRARIES=…`, `-DUSER_BLAS_LIBRARIES=…`  
  Explicitly points CMake to your system’s LAPACK/BLAS shared libraries when automatic detection fails (Debian/Ubuntu default paths are provided in the script).

---

## Examples

**Default (serial) build**
```bash
./ug4_install.sh
cd ug4/build && cmake --build . -j
```

**MPI + Neuro + SuperLU + ProMesh**
```bash
./ug4_install.sh -mpi -neuro -lu -promesh
cd ug4/build && cmake --build . -j
```

**Custom clone location (keeps `../ughub/ughub` working via symlink)**
```bash
./ug4_install.sh -mpi ~/src/ughub
```

**Override BLAS/LAPACK paths**
```bash
LAPACK_LIB_OVERRIDE=/usr/lib/x86_64-linux-gnu/liblapack.so BLAS_LIB_OVERRIDE=/usr/lib/x86_64-linux-gnu/libblas.so ./ug4_install.sh -lu
```

---

## Troubleshooting

- **“git not found” / “cmake not found”**  
  Install required tools, e.g. `sudo apt-get install git cmake build-essential`.

- **MPI requested but not found**  
  The script will fall back to serial compilers and set `-DPARALLEL=OFF`.  
  Install an MPI toolchain (e.g., `sudo apt-get install mpich` or `openmpi` variants).

- **BLAS/LAPACK not detected by CMake**  
  The script auto-retries with `-DUSER_LAPACK_LIBRARIES` and `-DUSER_BLAS_LIBRARIES`. Adjust with `LAPACK_LIB_OVERRIDE`/`BLAS_LIB_OVERRIDE` if your distro stores them elsewhere.

- **SuperLU6 build issues**  
  Ensure `plugins/SuperLU6/external/superlu/` exists (the script clones it when `-lu` is passed). Delete and re-run with `-lu` to refresh.
