# UG4 / ughub Windows install helper (PowerShell)
# - Uses Windows-style paths
# - Prints progress at each step
# - Creates missing directories
# - Stops on errors
# - Adds ughub to PATH (current session + persists to User PATH)
# - NEW: -lu flag installs SuperLU6 and wires external/superlu, adds -DSuperLU6=ON to CMake
# - NEW: -promesh flag adds -DProMesh=ON to CMake

param(
    [switch]$lu,        # pass -lu to install & enable SuperLU6
    [switch]$promesh    # pass -promesh to enable ProMesh build (-DProMesh=ON)
)

$ErrorActionPreference = 'Stop'

function Add-ToUserPath {
    param([string]$PathToAdd)
    if (-not (Test-Path $PathToAdd)) {
        Write-Host "WARNING: Path '$PathToAdd' does not exist; skipping PATH add." -ForegroundColor Yellow
        return
    }
    # Current process
    if (-not ($Env:Path -split ';' | Where-Object { $_ -eq $PathToAdd })) {
        $Env:Path = "$Env:Path;$PathToAdd"
    }
    # Persist to User PATH
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not ($userPath -split ';' | Where-Object { $_ -eq $PathToAdd })) {
        [Environment]::SetEnvironmentVariable('Path', "$userPath;$PathToAdd", 'User')
        Write-Host "Added to User PATH: $PathToAdd (you may need a new terminal for this to take effect)" -ForegroundColor Green
    }
}

# --- Directories ---
$HomeDir    = $HOME
$UghubDir   = Join-Path $HomeDir 'ughub'
$Ug4Dir     = Join-Path $HomeDir 'ug4'
$PluginsDir = Join-Path $Ug4Dir 'plugins'
$AppsDir    = Join-Path $Ug4Dir 'apps'
$BuildDir   = Join-Path $Ug4Dir 'build'

# SuperLU6 external dir (used when -lu is passed)
$SuperLUExternalDir = Join-Path $PluginsDir 'SuperLU6\external'

try {
    Write-Host "Changing directory to HOME: $HomeDir"
    Set-Location $HomeDir

    # --- Clone or update ughub ---
    if (-not (Test-Path $UghubDir)) {
        Write-Host "Cloning ughub repository into $UghubDir ..."
        git clone https://github.com/UG4/ughub
    } else {
        Write-Host "ughub already exists at $UghubDir. Pulling latest changes..."
        Set-Location $UghubDir
        git pull
    }

    # --- Add ughub to PATH ---
    Write-Host "Adding ughub to PATH..."
    Add-ToUserPath $UghubDir

    # --- Ensure ug4 directory structure ---
    Write-Host "Ensuring directories exist under $Ug4Dir ..."
    New-Item -ItemType Directory -Force -Path $Ug4Dir       | Out-Null
    New-Item -ItemType Directory -Force -Path $PluginsDir   | Out-Null
    New-Item -ItemType Directory -Force -Path $AppsDir      | Out-Null

    # --- Initialize ughub in ug4 ---
    Write-Host "Initializing ughub inside $Ug4Dir ..."
    Set-Location $Ug4Dir
    ughub init

    # --- Install Examples package ---
    Write-Host "Installing UG4 Examples ..."
    ughub install Examples

    # --- Add NeuroBox source ---
    Write-Host "Adding NeuroBox package source ..."
    ughub addsource neurobox https://github.com/NeuroBox3D/neurobox-packages.git

    # --- Install plugins ---
    Write-Host "Installing plugins: cable_neuron, neuro_collection, MembranePotentialMapping ..."
    Set-Location $PluginsDir
    ughub install cable_neuron neuro_collection MembranePotentialMapping

    # --- Install apps ---
    Write-Host "Installing apps: cable_neuron_app, calciumDynamics_app, MembranePotentialMapping_app ..."
    Set-Location $AppsDir
    ughub install cable_neuron_app calciumDynamics_app MembranePotentialMapping_app

    # --- OPTIONAL: SuperLU6 (-lu) ---
    if ($lu) {
        Write-Host "(-lu) Installing SuperLU6 plugin (from ug4 root) and wiring external/superlu ..." -ForegroundColor Cyan
        # Run ughub from ug4 root using relative path to sibling ughub script
        Set-Location $Ug4Dir
        $ughubRel = "..\ughub\ughub"
        if (-not (Test-Path $ughubRel)) {
            throw "Expected ughub script at '$ughubRel' relative to '$Ug4Dir' but it was not found."
        }

        & $ughubRel install SuperLU6

        # Ensure external dir exists
        New-Item -ItemType Directory -Force -Path $SuperLUExternalDir | Out-Null
        Set-Location $SuperLUExternalDir

        # Remove any existing 'superlu' folder
        $superluPath = Join-Path $SuperLUExternalDir 'superlu'
        if (Test-Path $superluPath) {
            Write-Host "Removing existing '$superluPath' ..."
            Remove-Item -Recurse -Force $superluPath
        }

        # Clone upstream SuperLU into external/superlu
        Write-Host "Cloning upstream SuperLU into '$superluPath' ..."
        git clone https://github.com/xiaoyeli/superlu.git superlu
    }

    # --- Configure build ---
    Write-Host "Creating build directory: $BuildDir"
    New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
    Set-Location $BuildDir

    # Build CMake flag list; append -DSuperLU6=ON if -lu is set; -DProMesh=ON if -promesh is set
    $cmakeFlags = @(
        '-DDIM=ALL',
        '-DCPU=1',
        '-DSTATIC_BUILD=ON',
        '-DCMAKE_BUILD_TYPE=Release',
        '-DLAPACK=OFF',
        '-DBLAS=OFF',
        '-DEMBEDDED_PLUGINS=ON',
        '-DConvectionDiffusion=ON',
        '-Dneuro_collection=ON',
        '-Dcable_neuron=ON',
        '-DMembranePotentialMapping=ON'
    )

    if ($lu) {
        Write-Host "(-lu) Enabling SuperLU6: adding -DSuperLU6=ON to CMake flags." -ForegroundColor Cyan
        $cmakeFlags += '-DSuperLU6=ON'
    }
    if ($promesh) {
        Write-Host "(-promesh) Enabling ProMesh: adding -DProMesh=ON to CMake flags." -ForegroundColor Cyan
        $cmakeFlags += '-DProMesh=ON'
    }

    Write-Host "Configuring UG4 with CMake (Release) ..." -ForegroundColor Cyan
    cmake @cmakeFlags ..

    # Build with Visual Studio (via CMake), using 4 parallel processes
    Write-Host "Building solution (Release) with 4 parallel processes via CMake/MSBuild..."
    cmake --build "$BuildDir" --config Release -- /m:6

    Write-Host "All steps completed. You can now build/run UG4 from: $BuildDir" -ForegroundColor Green
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Script aborted due to the error above." -ForegroundColor Red
    exit 1
}
finally {
    # Return to HOME to leave the shell in a known state
    Set-Location $HomeDir
}