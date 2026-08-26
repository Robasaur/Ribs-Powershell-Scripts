<#
_author_  = Rob Plumridge
_version_ = 3
_purpose_ = Intune Win32 removal of .NET 8 SDK and updater
#>
$ErrorActionPreference = "Stop"

# Configuration
$DotNetInstallDir = Join-Path $env:ProgramFiles "dotnet"
$SdkDir = Join-Path $DotNetInstallDir "sdk"
$AppRoot = "C:\ProgramData\Microsoft\DotNet8"
$LogDir  = Join-Path $AppRoot "Logs"
$LogFile = Join-Path $LogDir "Uninstall.log"
$TaskName = "Microsoft .NET 8 SDK Update"

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

# Main
try {
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }

    Write-Log "=========================================="
    Write-Log "Starting .NET 8 SDK uninstall"
    Write-Log "=========================================="

    Write-Log "Checking for scheduled task: $TaskName"

    $Task = Get-ScheduledTask `
        -TaskName $TaskName `
        -ErrorAction SilentlyContinue

    if ($Task) {
        Write-Log "Removing scheduled task."

        Unregister-ScheduledTask `
            -TaskName $TaskName `
            -Confirm:$false

        Write-Log "Scheduled task removed."
    }
    else {
        Write-Log "Scheduled task not found."
    }

    if (Test-Path $SdkDir) {
        $DotNet8SDKs = Get-ChildItem `
            -Path $SdkDir `
            -Directory `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -match '^8\.0\.\d+$'
            }

        if ($DotNet8SDKs) {
            foreach ($SDK in $DotNet8SDKs) {
                Write-Log "Removing .NET 8 SDK: $($SDK.Name)"

                Remove-Item `
                    -Path $SDK.FullName `
                    -Recurse `
                    -Force `
                    -ErrorAction Stop

                Write-Log "Removed .NET 8 SDK: $($SDK.Name)"
            }
        }
        else {
            Write-Log "No .NET 8 SDK versions found."
        }
    }
    else {
        Write-Log "SDK directory does not exist."
    }

    $RemainingSDKs = @()

    if (Test-Path $SdkDir) {
        $RemainingSDKs = Get-ChildItem `
            -Path $SdkDir `
            -Directory `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -match '^8\.0\.\d+$'
            }
    }

    if ($RemainingSDKs) {
        $RemainingNames = $RemainingSDKs.Name -join ", "

        throw "The following .NET 8 SDK versions remain installed: $RemainingNames"
    }

    Write-Log "Verified that no .NET 8 SDK versions remain."

    if (Test-Path $AppRoot) {
        Write-Log "Removing managed updater directory: $AppRoot"

        Remove-Item `
            -Path $AppRoot `
            -Recurse `
            -Force `
            -ErrorAction Stop

        Write-Log "Managed updater directory removed."
    }

    Write-Log "=========================================="
    Write-Log ".NET 8 SDK uninstall completed successfully"
    Write-Log "=========================================="

    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Log "Uninstall failed."

    exit 1
}