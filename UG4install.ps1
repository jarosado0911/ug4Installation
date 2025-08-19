<# 
UG4 / ughub Windows install helper (PowerShell)

Features
- Uses Windows-style paths; prints progress and stops on errors
- Creates missing directories; adds ughub to PATH (current session + User PATH)
- -lu       : installs SuperLU6, wires external/superlu, adds -DSuperLU6=ON
- -promesh  : adds -DProMesh=ON
- -mpi      : searches for MPI compilers; if missing:
              * auto-elevates
              * tries winget for Microsoft.MPI + Microsoft.MPI.Sdk
              * falls back to direct download + silent install
              * sets CMAKE_C/CXX to MPI compilers, enables -DPARALLEL=ON -DPCL_DEBUG_BARRIER=ON

Usage examples
  .\UG4Install.ps1 -mpi
  .\UG4Install.ps1 -mpi -lu -promesh
  .\UG4Install.ps1 -mpi -MsMpiRedistUrl "https://intranet/msmpisetup.exe" -MsMpiSdkUrl "https://intranet/msmpisdk.msi"
#>

param(
    [switch]$lu,                        # install & enable SuperLU6
    [switch]$promesh,                   # enable ProMesh (-DProMesh=ON)
    [switch]$mpi,                       # use MPI; auto-install MS-MPI if missing
    [string]$MsMpiRedistUrl = "https://download.microsoft.com/download/5/1/d/51d9f3aa-2c27-40d3-9a6c-6d5f7aab8c16/msmpisetup.exe",
    [string]$MsMpiSdkUrl    = "https://download.microsoft.com/download/5/1/d/51d9f3aa-2c27-40d3-9a6c-6d5f7aab8c16/msmpisdk.msi"
)

$ErrorActionPreference = 'Stop'

# ----------------- Helpers -----------------

function Add-ToUserPath {
    param([string]$PathToAdd)
    if (-not (Test-Path -LiteralPath $PathToAdd)) {
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
        Write-Host "Added to User PATH: $PathToAdd (new terminals pick this up)." -ForegroundColor Green
    }
}

function Find-CommandPath {
    param([string[]]$Names)
    foreach ($n in $Names) {
        $cmd = Get-Command $n -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    return $null
}

function Get-MPICompilerPair {
    # Try common names (Intel oneAPI MPI & MS-MPI)
    $cCandidates   = @('mpiicx','mpiicc','mpicc')
    $cxxCandidates = @('mpiicx','mpiicpc','mpicxx','mpic++')

    $mpiC   = Find-CommandPath -Names $cCandidates
    $mpiCXX = Find-CommandPath -Names $cxxCandidates
    if ($mpiC -and $mpiCXX) {
        return @{ C = $mpiC; CXX = $mpiCXX }
    }

    # Try standard MS-MPI location (even if PATH not updated yet)
    $msmpiBin = 'C:\Program Files\Microsoft MPI\Bin'
    $mpicc    = Join-Path $msmpiBin 'mpicc.exe'
    $mpicxx   = Join-Path $msmpiBin 'mpicxx.exe'
    if ( (Test-Path -LiteralPath $mpicc) -and (Test-Path -LiteralPath $mpicxx) ) {
        return @{ C = $mpicc; CXX = $mpicxx }
    }
    return $null
}

function Ensure-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "Elevation required. Relaunching as Administrator..." -ForegroundColor Yellow
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName  = "powershell.exe"
        $psi.Verb      = "runas"
        # Reconstruct current script and bound parameters
        $argList = @("-NoProfile","-ExecutionPolicy","Bypass","-File","`"$PSCommandPath`"")
        foreach ($k in $MyInvocation.BoundParameters.Keys) {
            $v = $MyInvocation.BoundParameters[$k]
            if ($v -is [switch]) {
                $argList += "-$k"
            } else {
                $argList += "-$k"
                $argList += "`"$v`""
            }
        }
        $psi.Arguments = ($argList -join ' ')
        [System.Diagnostics.Process]::Start($psi) | Out-Null
        exit 0
    }
}

function Invoke-WingetInstall {
    param([string]$Id)
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) { return $false }

    # Exact ID, machine scope, silent
    $args = @('install','--id', $Id,'--exact','--scope','machine','--silent',
              '--accept-package-agreements','--accept-source-agreements')
    Write-Host "winget $($args -join ' ')" -ForegroundColor DarkGray
    $p = Start-Process -FilePath $winget.Source -ArgumentList $args -Wait -PassThru
    if ($p.ExitCode -eq 0) { return $true }

    Write-Host "winget exit $($p.ExitCode). Refreshing sources then retrying..." -ForegroundColor Yellow
    Start-Process -FilePath $winget.Source -ArgumentList @('source','update') -Wait | Out-Null
    $p2 = Start-Process -FilePath $winget.Source -ArgumentList $args -Wait -PassThru
    return ($p2.ExitCode -eq 0)
}

function Install-MS_MPI {
    param([string]$RedistUrl, [string]$SdkUrl)

    Write-Host "Attempting Microsoft MPI install via winget..." -ForegroundColor Cyan
    $ok1 = Invoke-WingetInstall -Id 'Microsoft.MPI'
    $ok2 = Invoke-WingetInstall -Id 'Microsoft.MPI.Sdk'
    if ($ok1 -and $ok2) { return $true }

    Write-Host "winget path failed; falling back to direct download + silent install." -ForegroundColor Yellow
    $dl = Join-Path $env:TEMP "msmpi_dl"
    New-Item -ItemType Directory -Force -Path $dl | Out-Null
    $redistExe = Join-Path $dl "msmpisetup.exe"
    $sdkMsi    = Join-Path $dl "msmpisdk.msi"

    Write-Host "Downloading Redistributable from: $RedistUrl"
    Invoke-WebRequest -Uri $RedistUrl -OutFile $redistExe -UseBasicParsing
    Write-Host "Downloading SDK from: $SdkUrl"
    Invoke-WebRequest -Uri $SdkUrl -OutFile $sdkMsi -UseBasicParsing

    Write-Host "Installing MS-MPI Redistributable (silent)..." -ForegroundColor Cyan
    $pr = Start-Process -FilePath $redistExe -ArgumentList '/quiet','/norestart' -Wait -PassThru
    if ($pr.ExitCode -ne 0) { throw "MS-MPI redist installer failed: exit $($pr.ExitCode)" }

    Write-Host "Installing MS-MPI SDK (silent)..." -ForegroundColor Cyan
    $ps = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i',"`"$sdkMsi`"","/qn","/norestart") -Wait -PassThru
    if ($ps.ExitCode -ne 0) { throw "MS-MPI SDK installer failed: exit $($ps.ExitCode)" }

    # Update PATH for current session (installers usually set permanent PATH)
    $msmpiBin = 'C:\Program Files\Microsoft MPI\Bin'
    if (Test-Path -LiteralPath $msmpiBin) { Add-ToUserPath $msmpiBin }
    return $true
}

# ----------------- Layout -----------------

$HomeDir    = $HOME
$UghubDir   = Join-Path $HomeDir 'ughub'
$Ug4Dir     = Join-Path $HomeDir 'ug4'
$PluginsDir = Join-Path $Ug4Dir 'plugins'
$AppsDir    = Join-Path $Ug4Dir 'apps'
$BuildDir   = Join-Path $Ug4Dir 'build'
$SuperLUExternalDir = Join-Path $PluginsDir 'SuperLU6\external'

try {
    if ($mpi) { Ensure-Admin }

    Write-Host "Changing directory to HOME: $HomeDir"
    Set-Location $HomeDir

    # --- Clone or update ughub ---
    if (-not (Test-Path -LiteralPath $UghubDir)) {
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
    New-Item -ItemType Directory -Force -Path $Ug4Dir     | Out-Null
    New-Item -ItemType Directory -Force -Path $PluginsDir | Out-Null
    New-Item -ItemType Directory -Force -Path $AppsDir    | Out-Null

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
        Write-Host "(-lu) Installing SuperLU6 and wiring external/superlu ..." -ForegroundColor Cyan
        Set-Location $Ug4Dir
        $ughubRel = "..\ughub\ughub"
        if (-not (Test-Path -LiteralPath $ughubRel)) {
            throw "Expected ughub script at '$ughubRel' relative to '$Ug4Dir' but it was not found."
        }
        & $ughubRel install SuperLU6

        New-Item -ItemType Directory -Force -Path $SuperLUExternalDir | Out-Null
        Set-Location $SuperLUExternalDir
        $superluPath = Join-Path $SuperLUExternalDir 'superlu'
        if (Test-Path -LiteralPath $superluPath) {
            Write-Host "Removing existing '$superluPath' ..."
            Remove-Item -Recurse -Force $superluPath
        }
        Write-Host "Cloning upstream SuperLU into '$superluPath' ..."
        git clone https://github.com/xiaoyeli/superlu.git superlu
    }

    # --- Configure build ---
    Write-Host "Creating build directory: $BuildDir"
    New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
    Set-Location $BuildDir

    # Base CMake flags
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
    if ($lu)      { $cmakeFlags += '-DSuperLU6=ON' }
    if ($promesh) { $cmakeFlags += '-DProMesh=ON'  }

    # --- MPI path: detect or install ---
    if ($mpi) {
        Write-Host "(-mpi) Requested. Searching for MPI compilers..." -ForegroundColor Cyan
        $pair = Get-MPICompilerPair
        if (-not $pair) {
            Write-Host "MPI compilers not found. Installing Microsoft MPI (Redistributable + SDK)..." -ForegroundColor Yellow
            $ok = Install-MS_MPI -RedistUrl $MsMpiRedistUrl -SdkUrl $MsMpiSdkUrl
            if (-not $ok) { throw "Microsoft MPI installation failed." }
            $pair = Get-MPICompilerPair
        }
        if (-not $pair) { throw "MS-MPI installed, but mpi compilers were not found." }

        Write-Host "Using MPI C:   $($pair.C)"   -ForegroundColor Green
        Write-Host "Using MPI C++: $($pair.CXX)" -ForegroundColor Green

        # Quote paths for spaces
        $cmakeFlags += "-DCMAKE_C_COMPILER=`"$($pair.C)`""
        $cmakeFlags += "-DCMAKE_CXX_COMPILER=`"$($pair.CXX)`""
        $cmakeFlags += '-DPARALLEL=ON'
        $cmakeFlags += '-DPCL_DEBUG_BARRIER=ON'
    }

    Write-Host "Configuring UG4 with CMake (Release) ..." -ForegroundColor Cyan
    cmake @cmakeFlags ..

    # Build with Visual Studio (via CMake) using multiple processes
    Write-Host "Building solution (Release) with parallel MSBuild..." -ForegroundColor Cyan
    cmake --build "$BuildDir" --config Release -- /m:6

    Write-Host "All steps completed. You can now build/run UG4 from: $BuildDir" -ForegroundColor Green
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Script aborted due to the error above." -ForegroundColor Red
    exit 1
}
finally {
    Set-Location $HomeDir
}
