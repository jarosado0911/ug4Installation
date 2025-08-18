# System Information Report Script
# Prints computer specs, OS details, CPU, RAM, and Visual Studio compilers

Write-Host "=== System Information Report ===" -ForegroundColor Cyan

# --- OS Information ---
Write-Host "`n--- Operating System ---"
Get-ComputerInfo | Select-Object OsName, OsArchitecture, WindowsVersion, WindowsBuildLabEx | Format-List

# --- CPU Information ---
Write-Host "`n--- CPU Information ---"
Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed | Format-List

# --- RAM Information ---
Write-Host "`n--- RAM Information ---"
$ram = Get-CimInstance Win32_PhysicalMemory
$ram | ForEach-Object {
    [PSCustomObject]@{
        Manufacturer = $_.Manufacturer
        CapacityGB   = "{0:N2}" -f ($_.Capacity / 1GB)
        SpeedMHz     = $_.Speed
    }
} | Format-Table -AutoSize
$totalRAM = ($ram | Measure-Object -Property Capacity -Sum).Sum
Write-Host ("Total Installed RAM: {0:N2} GB" -f ($totalRAM / 1GB)) -ForegroundColor Green

# --- GPU Information ---
Write-Host "`n--- GPU Information ---"
Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, AdapterRAM | Format-Table -AutoSize

# --- Visual Studio Compiler Detection ---
Write-Host "`n--- Visual Studio Compilers ---"
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
    & $vswhere -all -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath | ForEach-Object {
            $cl = Join-Path $_ "VC\Tools\MSVC"
            if (Test-Path $cl) {
                Get-ChildItem $cl | ForEach-Object {
                    Write-Host "Visual C++ Compiler found: $($_.FullName)"
                }
            }
        }
} else {
    Write-Host "vswhere.exe not found. Cannot detect Visual Studio compilers." -ForegroundColor Yellow
}

Write-Host "`n=== Report Complete ===" -ForegroundColor Cyan