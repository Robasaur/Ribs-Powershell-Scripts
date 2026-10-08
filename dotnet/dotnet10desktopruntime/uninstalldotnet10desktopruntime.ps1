<#
_author_  = Rob Plumridge
_version_ = 5
_purpose_ = Intune Win32 removal of .NET 10 Desktop Runtime
#>
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# Configuration
$ProgramFiles64 = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
$DotnetExe = Join-Path $ProgramFiles64 "dotnet\dotnet.exe"
$AppRoot = "C:\ProgramData\Microsoft\DotNet10DesktopRuntime"
$LogDir  = Join-Path $AppRoot "Logs"
$LogFile = Join-Path $LogDir "Uninstall.log"
$BundleLogFile = Join-Path $LogDir "WindowsDesktopRuntime-Uninstall.log"
$ManifestFile = Join-Path $AppRoot "InstalledRuntimes.json"
$DownloadDir = Join-Path $AppRoot "Download"
$UninstallKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
$SuccessExitCodes = @(0, 3010, 1641)
$MaxLogBytes = 1MB
$script:FailureExitCode = 1

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

    Write-Host $Message
}

function Invoke-WithRetry {
    param (
        [Parameter(Mandatory)]
        [string]$Description,

        [Parameter(Mandatory)]
        [scriptblock]$Action,

        [int]$Attempts = 3
    )

    for ($Attempt = 1; $Attempt -le $Attempts; $Attempt++) {
        try {
            return & $Action
        }
        catch {
            if ($Attempt -eq $Attempts) {
                throw
            }

            $Delay = $Attempt * 15
            Write-Log "$Description failed (attempt $Attempt of $Attempts): $($_.Exception.Message) Retrying in $Delay seconds..."
            Start-Sleep -Seconds $Delay
        }
    }
}

function Get-RuntimeListing {
    if (-not (Test-Path $DotnetExe)) {
        return $null
    }

    # Windows PowerShell 5.1 turns native stderr into a terminating error when ErrorActionPreference is Stop
    $PreviousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    try {
        $HostOutput = & $DotnetExe --list-runtimes 2>&1
        $HostExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousPreference
    }

    if ($HostExitCode -ne 0) {
        Write-Log "The .NET host failed to start (exit code $HostExitCode): $(($HostOutput | ForEach-Object { "$_" }) -join ' ')"
        return $null
    }

    return @($HostOutput | ForEach-Object { "$_" })
}

function Write-InventoryLog {
    param (
        [Parameter(Mandatory)]
        [string]$Label
    )

    $Listing = Get-RuntimeListing

    if ($null -eq $Listing) {
        Write-Log "${Label}: no working .NET host."
        return
    }

    Write-Log "${Label}:"

    foreach ($Line in $Listing) {
        Write-Log "  $Line"
    }
}

function Get-BundleUninstaller {
    param (
        [Parameter(Mandatory)]
        [string]$Version
    )

    $Entry = Get-ItemProperty -Path $UninstallKeys -ErrorAction SilentlyContinue |
        Where-Object {
            $_.DisplayName -eq "Microsoft Windows Desktop Runtime - $Version (x64)" -and
            $_.BundleCachePath -and
            (Test-Path $_.BundleCachePath)
        } |
        Select-Object -First 1

    if ($Entry) {
        return $Entry.BundleCachePath
    }

    return $null
}

function Save-VerifiedInstaller {
    param (
        [Parameter(Mandatory)]
        $Manifest
    )

    if (Test-Path $DownloadDir) {
        Remove-Item -Path $DownloadDir -Recurse -Force
    }

    New-Item -Path $DownloadDir -ItemType Directory -Force | Out-Null

    $InstallerPath = Join-Path $DownloadDir ([IO.Path]::GetFileName(([uri]$Manifest.InstallerUrl).AbsolutePath))

    Write-Log "Cached bundle not found. Downloading $($Manifest.InstallerUrl)"

    Invoke-WithRetry -Description "Installer download" -Action {
        Invoke-WebRequest `
            -Uri $Manifest.InstallerUrl `
            -OutFile $InstallerPath `
            -UseBasicParsing
    }

    $ActualHash = (Get-FileHash -Path $InstallerPath -Algorithm SHA512).Hash

    if ($ActualHash -ne $Manifest.InstallerSha512) {
        throw "SHA-512 mismatch for $InstallerPath. Expected $($Manifest.InstallerSha512), got $ActualHash."
    }

    $Signature = Get-AuthenticodeSignature -FilePath $InstallerPath

    if ($Signature.Status -ne "Valid" -or $Signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
        throw "Installer signature is not a valid Microsoft signature: $($Signature.Status) $($Signature.SignerCertificate.Subject)"
    }

    Write-Log "Verified downloaded installer SHA-512 and Authenticode signature."

    return $InstallerPath
}

# Main
try {
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }

    if ((Test-Path $LogFile) -and (Get-Item $LogFile).Length -gt $MaxLogBytes) {
        Move-Item -Path $LogFile -Destination "$LogFile.old" -Force
    }

    Write-Log "=========================================="
    Write-Log "Starting .NET 10 Desktop Runtime uninstall"
    Write-Log "=========================================="

    Write-InventoryLog -Label "Runtime inventory before uninstall"

    if (-not (Test-Path $ManifestFile)) {
        Write-Log "No runtime ownership manifest found at $ManifestFile. No runtimes are owned by this package; nothing was removed."
        exit 0
    }

    $Manifest = Get-Content -Path $ManifestFile -Raw | ConvertFrom-Json
    $Version = $Manifest.DesktopRuntimeVersion

    if (-not $Version) {
        throw "The runtime ownership manifest does not contain a DesktopRuntimeVersion."
    }

    $ExitCode = 0

    if ($Manifest.PreExisting) {
        Write-Log "Windows Desktop Runtime $Version was already installed before this package ran. It will not be removed."
    }
    else {
        try {
            $InstallerPath = Get-BundleUninstaller -Version $Version

            if ($InstallerPath) {
                Write-Log "Using cached Windows Desktop Runtime bundle: $InstallerPath"
            }
            else {
                $InstallerPath = Save-VerifiedInstaller -Manifest $Manifest
            }

            Write-Log "Running Windows Desktop Runtime $Version uninstall: /uninstall /quiet /norestart"

            $Process = Start-Process `
                -FilePath $InstallerPath `
                -ArgumentList "/uninstall /quiet /norestart /log `"$BundleLogFile`"" `
                -Wait `
                -PassThru

            $ExitCode = $Process.ExitCode
            Write-Log "Windows Desktop Runtime uninstall exit code: $ExitCode"

            if ($SuccessExitCodes -notcontains $ExitCode) {
                $script:FailureExitCode = $ExitCode
                throw "The Windows Desktop Runtime uninstall failed with exit code $ExitCode. See $BundleLogFile."
            }
        }
        finally {
            if (Test-Path $DownloadDir) {
                Remove-Item -Path $DownloadDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        $Listing = Get-RuntimeListing

        if ($Listing -and ($Listing | Where-Object { $_ -match "^Microsoft\.WindowsDesktop\.App\s+$([regex]::Escape($Version))\s" })) {
            throw "Microsoft.WindowsDesktop.App $Version is still reported by dotnet.exe after uninstall."
        }

        Write-Log "Verified Microsoft.WindowsDesktop.App $Version was removed."

        if ((Test-Path (Join-Path $ProgramFiles64 "dotnet\shared")) -and $null -eq $Listing) {
            Write-Log "WARNING: Other .NET runtime folders remain but the .NET host cannot start. Repair the remaining .NET installation."
        }
    }

    Write-InventoryLog -Label "Runtime inventory after uninstall"

    Remove-Item -Path $ManifestFile -Force
    Write-Log "Runtime ownership manifest removed."

    Write-Log "=========================================="
    Write-Log ".NET 10 Desktop Runtime uninstall completed successfully"
    Write-Log "=========================================="

    exit $ExitCode
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Log "Uninstall failed."

    exit $script:FailureExitCode
}
