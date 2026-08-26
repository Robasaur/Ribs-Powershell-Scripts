<#
_author_  = Rob Plumridge
_version_ = 3
_purpose_ = Intune Win32 installation of latest .NET 8 SDK (x64)
#>
$ErrorActionPreference = "Stop"

# Configuration
$DotNetInstallDir = Join-Path $env:ProgramFiles "dotnet"
$AppRoot = "C:\ProgramData\Microsoft\DotNet8"
$LogDir  = Join-Path $AppRoot "Logs"
$LogFile = Join-Path $LogDir "Install.log"
$UpdaterSource = Join-Path $PSScriptRoot "updatedotnet8sdk.ps1"
$UpdaterTarget = Join-Path $AppRoot "updatedotnet8sdk.ps1"
$TaskName = "Microsoft .NET 8 SDK Update"
$UpdateDayOfWeek = "Wednesday"
$UpdateTime = "11:00"
$RandomDelayMinutes = 60

# Functions
function Write-Log {
    param (
        [Parameter(Mandatory)]
        [string]$Message
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }

    "$Timestamp - $Message" |
        Out-File -FilePath $LogFile -Append -Encoding utf8

    Write-Output $Message
}

function Install-LatestDotNet8 {
    param (
        [Parameter(Mandatory)]
        [string]$InstallDir
    )

    $ScriptPath = Join-Path $env:TEMP "dotnet-install-$([guid]::NewGuid()).ps1"

    try {
        Write-Log "Downloading Microsoft dotnet-install.ps1..."

        Invoke-WebRequest `
            -Uri "https://dot.net/v1/dotnet-install.ps1" `
            -OutFile $ScriptPath `
            -UseBasicParsing `
            -ErrorAction Stop

        if (-not (Test-Path $ScriptPath)) {
            throw "Microsoft dotnet-install.ps1 was not downloaded."
        }

        Write-Log "Microsoft installation script downloaded."
        Write-Log "Installing latest GA .NET 8 SDK..."

        & $ScriptPath `
            -Channel "8.0" `
            -Quality "GA" `
            -Architecture "x64" `
            -InstallDir $InstallDir `
            -NoPath

        if ($LASTEXITCODE -ne 0) {
            throw "dotnet-install.ps1 exited with code $LASTEXITCODE."
        }

        Write-Log ".NET installation script completed successfully."
    }
    finally {
        if (Test-Path $ScriptPath) {
            Remove-Item `
                -Path $ScriptPath `
                -Force `
                -ErrorAction SilentlyContinue

            Write-Log "Temporary installation script removed."
        }
    }
}

# Main
try {
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }

    Write-Log "=========================================="
    Write-Log "Starting .NET 8 SDK installation"
    Write-Log "=========================================="

    if (-not [Environment]::Is64BitOperatingSystem) {
        throw "This package requires a 64-bit operating system."
    }

    Write-Log "Operating system architecture: x64"

    if (-not (Test-Path $AppRoot)) {
        New-Item -Path $AppRoot -ItemType Directory -Force | Out-Null
    }

    Install-LatestDotNet8 -InstallDir $DotNetInstallDir

    $DotnetExe = Join-Path $DotNetInstallDir "dotnet.exe"

    if (-not (Test-Path $DotnetExe)) {
        throw "dotnet.exe was not found at $DotnetExe."
    }

    Write-Log "dotnet.exe verified: $DotnetExe"

    $SDKOutput = & $DotnetExe --list-sdks 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "Unable to query installed .NET SDKs."
    }

    $DotNet8SDKs = $SDKOutput |
        Where-Object {
            $_ -match '^8\.0\.\d+\s'
        }

    if (-not $DotNet8SDKs) {
        throw "No .NET 8 SDK was detected after installation."
    }

    foreach ($SDK in $DotNet8SDKs) {
        Write-Log "Detected .NET 8 SDK: $SDK"
    }

    if (-not (Test-Path $UpdaterSource)) {
        throw "updatedotnet8sdk.ps1 was not found in the package directory: $UpdaterSource"
    }

    Write-Log "Installing persistent update script."

    Copy-Item `
        -Path $UpdaterSource `
        -Destination $UpdaterTarget `
        -Force

    Write-Log "Updater installed at: $UpdaterTarget"

    Write-Log "Creating scheduled task."

    $RandomDelay = New-TimeSpan -Minutes $RandomDelayMinutes

    $Trigger = New-ScheduledTaskTrigger `
        -Weekly `
        -WeeksInterval 1 `
        -DaysOfWeek $UpdateDayOfWeek `
        -At $UpdateTime `
        -RandomDelay $RandomDelay

    $PowerShellPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

    $Action = New-ScheduledTaskAction `
        -Execute $PowerShellPath `
        -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$UpdaterTarget`""

    $Principal = New-ScheduledTaskPrincipal `
        -UserId "SYSTEM" `
        -LogonType ServiceAccount `
        -RunLevel Highest

    $Settings = New-ScheduledTaskSettingsSet `
        -StartWhenAvailable `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Hours 2)

    $ExistingTask = Get-ScheduledTask `
        -TaskName $TaskName `
        -ErrorAction SilentlyContinue

    if ($ExistingTask) {
        Write-Log "Existing scheduled task found. Replacing it."

        Unregister-ScheduledTask `
            -TaskName $TaskName `
            -Confirm:$false
    }

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $Action `
        -Trigger $Trigger `
        -Principal $Principal `
        -Settings $Settings `
        -Description "Updates the Microsoft .NET 8 SDK using Microsoft's official installation script." `
        -Force | Out-Null

    Write-Log "Scheduled task created successfully."
    Write-Log "Task name: $TaskName"
    Write-Log "Schedule: Every $UpdateDayOfWeek at $UpdateTime"
    Write-Log "Random delay: 0-$RandomDelayMinutes minutes"

    $RegisteredTask = Get-ScheduledTask `
        -TaskName $TaskName `
        -ErrorAction SilentlyContinue

    if (-not $RegisteredTask) {
        throw "Scheduled task registration could not be verified."
    }

    Write-Log "Scheduled task verified."

    Write-Log "=========================================="
    Write-Log ".NET 8 SDK installation completed"
    Write-Log "=========================================="

    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Log "Installation failed."

    exit 1
}