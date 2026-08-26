<#
_author_  = Rob Plumridge
_version_ = 3
_purpose_ = Weekly update of the latest GA .NET 8 SDK
#>
$ErrorActionPreference = "Stop"

# Configuration
$DotNetInstallDir = Join-Path $env:ProgramFiles "dotnet"
$AppRoot = "C:\ProgramData\Microsoft\DotNet8"
$LogDir  = Join-Path $AppRoot "Logs"
$LogFile = Join-Path $LogDir "Update.log"
$MaxAttempts = 3
$RetryDelaysMinutes = @(
    5,
    10
)
$DotNetInstallScriptUri = "https://dot.net/v1/dotnet-install.ps1"
$EventSource = "Microsoft .NET 8 SDK Update"
$EventLog = "Application"
$EventId = 1001

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
}

function Get-InstalledDotNet8SDKs {
    $DotnetExe = Join-Path $DotNetInstallDir "dotnet.exe"

    if (-not (Test-Path $DotnetExe)) {
        return @()
    }

    try {
        $Output = & $DotnetExe --list-sdks 2>$null

        if ($LASTEXITCODE -ne 0) {
            return @()
        }

        $Versions = foreach ($Line in $Output) {
            if ($Line -match '^8\.0\.(\d+)\s') {
                try {
                    [version]$Matches[0]
                }
                catch {
                    continue
                }
            }
        }

        return @(
            $Versions |
                Sort-Object -Descending
        )
    }
    catch {
        return @()
    }
}

function Get-LatestDotNet8SDK {
    param (
        [Parameter(Mandatory)]
        [string]$ScriptPath
    )

    Write-Log "Determining latest GA .NET 8 SDK."

    $DryRunOutput = & $ScriptPath `
        -Channel "8.0" `
        -Quality "GA" `
        -Architecture "x64" `
        -InstallDir $DotNetInstallDir `
        -NoPath `
        -DryRun 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "dotnet-install.ps1 failed while determining the latest SDK."
    }

    foreach ($Line in $DryRunOutput) {
        Write-Log "Installer: $Line"
    }

    $Version = $null

    foreach ($Line in $DryRunOutput) {
        if ($Line -match '8\.0\.\d+') {
            $Candidate = [regex]::Match(
                $Line,
                '8\.0\.\d+'
            ).Value

            if ($Candidate) {
                try {
                    $Version = [version]$Candidate
                    break
                }
                catch {
                    continue
                }
            }
        }
    }

    if (-not $Version) {
        throw "Unable to determine latest .NET 8 SDK version from installer output."
    }

    return $Version
}

function Write-FailureEvent {
    param (
        [Parameter(Mandatory)]
        [string]$Message
    )

    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
            New-EventLog `
                -LogName $EventLog `
                -Source $EventSource
        }

        Write-EventLog `
            -LogName $EventLog `
            -Source $EventSource `
            -EventId $EventId `
            -EntryType Warning `
            -Message $Message
    }
    catch {
        Write-Log "WARNING: Unable to write Windows Event Log entry: $($_.Exception.Message)"
    }
}

# Main
try {
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }

    Write-Log "=========================================="
    Write-Log "Starting .NET 8 SDK update"
    Write-Log "=========================================="

    if (-not [Environment]::Is64BitOperatingSystem) {
        throw "Operating system is not 64-bit."
    }

    $InstalledSDKs = Get-InstalledDotNet8SDKs

    if ($InstalledSDKs.Count -gt 0) {
        $InstalledLatest = $InstalledSDKs |
            Sort-Object -Descending |
            Select-Object -First 1

        Write-Log "Currently installed latest .NET 8 SDK: $InstalledLatest"
    }
    else {
        Write-Log "No .NET 8 SDK currently detected."
        $InstalledLatest = [version]"0.0.0"
    }

    $Successful = $false

    for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
        Write-Log "Update attempt $Attempt of $MaxAttempts."

        $ScriptPath = Join-Path `
            $env:TEMP `
            "dotnet-install-$([guid]::NewGuid()).ps1"

        try {
            Write-Log "Downloading Microsoft dotnet-install.ps1."

            Invoke-WebRequest `
                -Uri $DotNetInstallScriptUri `
                -OutFile $ScriptPath `
                -UseBasicParsing `
                -ErrorAction Stop

            if (-not (Test-Path $ScriptPath)) {
                throw "Microsoft installation script was not downloaded."
            }

            Write-Log "Microsoft installation script downloaded."

            $LatestSDK = Get-LatestDotNet8SDK `
                -ScriptPath $ScriptPath

            Write-Log "Latest available GA .NET 8 SDK: $LatestSDK"

            if ($InstalledLatest -ge $LatestSDK) {
                Write-Log "Installed SDK $InstalledLatest is already current."
                Write-Log "No update required."

                $Successful = $true
                break
            }

            Write-Log "Newer SDK available."
            Write-Log "Installing $LatestSDK."

            & $ScriptPath `
                -Channel "8.0" `
                -Quality "GA" `
                -Architecture "x64" `
                -InstallDir $DotNetInstallDir `
                -NoPath

            if ($LASTEXITCODE -ne 0) {
                throw "dotnet-install.ps1 exited with code $LASTEXITCODE."
            }

            Write-Log "Installation command completed."

            $NewInstalledSDKs = Get-InstalledDotNet8SDKs

            if ($NewInstalledSDKs.Count -eq 0) {
                throw "No .NET 8 SDK detected after installation."
            }

            $NewLatestSDK = $NewInstalledSDKs |
                Sort-Object -Descending |
                Select-Object -First 1

            Write-Log "Latest installed .NET 8 SDK: $NewLatestSDK"

            if ($NewLatestSDK -lt $LatestSDK) {
                throw "Expected SDK $LatestSDK but installed SDK is $NewLatestSDK."
            }

            Write-Log "Successfully updated .NET 8 SDK to $NewLatestSDK."

            $Successful = $true
            break
        }
        catch {
            Write-Log "Attempt $Attempt failed: $($_.Exception.Message)"

            if ($Attempt -lt $MaxAttempts) {
                $DelayMinutes = $RetryDelaysMinutes[$Attempt - 1]

                Write-Log "Waiting $DelayMinutes minutes before retry."

                Start-Sleep `
                    -Seconds ($DelayMinutes * 60)
            }
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

    if ($Successful) {
        Write-Log "=========================================="
        Write-Log ".NET 8 SDK update completed successfully"
        Write-Log "=========================================="

        exit 0
    }

    $FailureMessage = @"
Microsoft .NET 8 SDK update failed after $MaxAttempts attempts.

The existing .NET 8 SDK installation has been left unchanged.

Check the update log for further information:

$LogFile
"@

    Write-Log "=========================================="
    Write-Log ".NET 8 SDK update FAILED"
    Write-Log "All $MaxAttempts attempts failed."
    Write-Log "Existing SDK installation has been left unchanged."
    Write-Log "=========================================="

    Write-FailureEvent -Message $FailureMessage

    exit 1
}
catch {
    $FailureMessage = @"
Microsoft .NET 8 SDK update failed unexpectedly.

The existing .NET 8 SDK installation has been left unchanged.

Error:
$($_.Exception.Message)

Check the update log for further information:

$LogFile
"@

    Write-Log "FATAL ERROR: $($_.Exception.Message)"

    Write-FailureEvent -Message $FailureMessage

    exit 1
}