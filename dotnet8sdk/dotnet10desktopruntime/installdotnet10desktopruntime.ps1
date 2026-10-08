<#
_author_  = Rob Plumridge
_version_ = 5
_purpose_ = Intune Win32 installation of latest .NET 10 Desktop Runtime (x64)
#>
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# Configuration
$ProgramFiles64 = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
$DotnetExe = Join-Path $ProgramFiles64 "dotnet\dotnet.exe"
$AppRoot = "C:\ProgramData\Microsoft\DotNet10DesktopRuntime"
$LogDir  = Join-Path $AppRoot "Logs"
$LogFile = Join-Path $LogDir "Install.log"
$BundleLogFile = Join-Path $LogDir "WindowsDesktopRuntime-Install.log"
$ManifestFile = Join-Path $AppRoot "InstalledRuntimes.json"
$DownloadDir = Join-Path $AppRoot "Download"
$ReleaseMetadataUri = "https://builds.dotnet.microsoft.com/dotnet/release-metadata/10.0/releases.json"
$SharedFxRegistryRoot = "HKLM:\SOFTWARE\WOW6432Node\dotnet\Setup\InstalledVersions\x64\sharedfx"
$RequiredVersion = [version]"10.0.12"
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

function Get-DotNetInventory {
    $Inventory = [pscustomobject]@{
        HostWorks = $false
        Runtimes  = @()
    }

    if (-not (Test-Path $DotnetExe)) {
        Write-Log "dotnet.exe not found: $DotnetExe"
        return $Inventory
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
        return $Inventory
    }

    $Inventory.HostWorks = $true
    $Inventory.Runtimes = @(
        foreach ($Line in $HostOutput) {
            if ("$Line" -match '^(Microsoft\.[\w\.]+)\s+(\d+\.\d+\.\d+)\s') {
                [pscustomobject]@{
                    Family  = $Matches[1]
                    Version = [version]$Matches[2]
                }
            }
        }
    )

    return $Inventory
}

function Write-InventoryLog {
    param (
        [Parameter(Mandatory)]
        [string]$Label,

        [Parameter(Mandatory)]
        $Inventory
    )

    if (-not $Inventory.HostWorks) {
        Write-Log "${Label}: no working .NET host."
        return
    }

    Write-Log "${Label}:"

    foreach ($Runtime in $Inventory.Runtimes) {
        Write-Log "  $($Runtime.Family) $($Runtime.Version)"
    }
}

function Test-RuntimeRegistered {
    param (
        [Parameter(Mandatory)]
        [string]$Family,

        [Parameter(Mandatory)]
        [version]$Version
    )

    $FamilyKey = Get-Item -Path (Join-Path $SharedFxRegistryRoot $Family) -ErrorAction SilentlyContinue

    return [bool]($FamilyKey -and ($FamilyKey.GetValueNames() -contains $Version.ToString()))
}

function Test-TargetRuntimeInstalled {
    param (
        [Parameter(Mandatory)]
        $Inventory,

        [Parameter(Mandatory)]
        $Release
    )

    if (-not $Inventory.HostWorks) {
        return $false
    }

    $Required = @(
        @{ Family = "Microsoft.NETCore.App"; Version = $Release.CoreVersion },
        @{ Family = "Microsoft.WindowsDesktop.App"; Version = $Release.DesktopVersion }
    )

    foreach ($Item in $Required) {
        $Present = $Inventory.Runtimes |
            Where-Object { $_.Family -eq $Item.Family -and $_.Version -eq $Item.Version }

        if (-not $Present) {
            Write-Log "$($Item.Family) $($Item.Version) is not reported by dotnet.exe."
            return $false
        }

        if (-not (Test-RuntimeRegistered -Family $Item.Family -Version $Item.Version)) {
            Write-Log "$($Item.Family) $($Item.Version) is present on disk but not registered under $SharedFxRegistryRoot."
            return $false
        }
    }

    return $true
}

function Get-LatestDesktopRuntimeRelease {
    Write-Log "Reading .NET 10 release metadata: $ReleaseMetadataUri"

    $Metadata = Invoke-WithRetry -Description "Release metadata download" -Action {
        Invoke-RestMethod -Uri $ReleaseMetadataUri -UseBasicParsing
    }
    $LatestRelease = $Metadata.'latest-release'

    if ($LatestRelease -notmatch '^\d+\.\d+\.\d+$') {
        throw "The latest .NET 10 release '$LatestRelease' is not a GA release."
    }

    $Release = $Metadata.releases |
        Where-Object { $_.'release-version' -eq $LatestRelease } |
        Select-Object -First 1

    if (-not $Release) {
        throw "Release $LatestRelease was not found in the .NET 10 release metadata."
    }

    $InstallerFile = $Release.windowsdesktop.files |
        Where-Object { $_.rid -eq "win-x64" -and $_.name -like "*.exe" } |
        Select-Object -First 1

    if (-not $InstallerFile) {
        throw "No x64 Windows Desktop Runtime installer is listed for release $LatestRelease."
    }

    [pscustomobject]@{
        DesktopVersion = [version]$Release.windowsdesktop.version
        CoreVersion    = [version]$Release.runtime.version
        Url            = $InstallerFile.url
        Sha512         = $InstallerFile.hash
    }
}

function Save-VerifiedInstaller {
    param (
        [Parameter(Mandatory)]
        $Release
    )

    if (Test-Path $DownloadDir) {
        Remove-Item -Path $DownloadDir -Recurse -Force
    }

    New-Item -Path $DownloadDir -ItemType Directory -Force | Out-Null

    $InstallerPath = Join-Path $DownloadDir ([IO.Path]::GetFileName(([uri]$Release.Url).AbsolutePath))

    Write-Log "Downloading $($Release.Url)"

    Invoke-WithRetry -Description "Installer download" -Action {
        Invoke-WebRequest `
            -Uri $Release.Url `
            -OutFile $InstallerPath `
            -UseBasicParsing
    }

    $ActualHash = (Get-FileHash -Path $InstallerPath -Algorithm SHA512).Hash

    if ($ActualHash -ne $Release.Sha512) {
        throw "SHA-512 mismatch for $InstallerPath. Expected $($Release.Sha512), got $ActualHash."
    }

    Write-Log "Verified installer SHA-512 against Microsoft release metadata."

    $Signature = Get-AuthenticodeSignature -FilePath $InstallerPath

    if ($Signature.Status -ne "Valid" -or $Signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
        throw "Installer signature is not a valid Microsoft signature: $($Signature.Status) $($Signature.SignerCertificate.Subject)"
    }

    Write-Log "Verified installer Authenticode signature: $($Signature.SignerCertificate.Subject)"

    return $InstallerPath
}

function Invoke-DesktopRuntimeBundle {
    param (
        [Parameter(Mandatory)]
        [string]$InstallerPath,

        [Parameter(Mandatory)]
        [ValidateSet("install", "repair")]
        [string]$Action
    )

    Write-Log "Running Windows Desktop Runtime installer: /$Action /quiet /norestart"

    $Process = Start-Process `
        -FilePath $InstallerPath `
        -ArgumentList "/$Action /quiet /norestart /log `"$BundleLogFile`"" `
        -Wait `
        -PassThru

    Write-Log "Windows Desktop Runtime installer /$Action exit code: $($Process.ExitCode)"

    return $Process.ExitCode
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
    Write-Log "Starting .NET 10 Desktop Runtime installation"
    Write-Log "=========================================="

    if (-not [Environment]::Is64BitOperatingSystem) {
        throw "This package requires a 64-bit operating system."
    }

    $InventoryBefore = Get-DotNetInventory
    Write-InventoryLog -Label "Runtime inventory before installation" -Inventory $InventoryBefore

    $Release = Get-LatestDesktopRuntimeRelease
    Write-Log "Latest GA Windows Desktop Runtime: $($Release.DesktopVersion) (Microsoft.NETCore.App $($Release.CoreVersion))"

    if ($Release.DesktopVersion -lt $RequiredVersion -or $Release.CoreVersion -lt $RequiredVersion) {
        throw "The latest GA release is older than the required minimum $RequiredVersion."
    }

    $PreExisting = Test-TargetRuntimeInstalled -Inventory $InventoryBefore -Release $Release
    $ExitCode = 0

    if ($PreExisting) {
        Write-Log "Windows Desktop Runtime $($Release.DesktopVersion) is already installed and registered. No installation required."
    }
    else {
        try {
            $InstallerPath = Save-VerifiedInstaller -Release $Release
            $ExitCode = Invoke-DesktopRuntimeBundle -InstallerPath $InstallerPath -Action install

            if ($SuccessExitCodes -notcontains $ExitCode) {
                $script:FailureExitCode = $ExitCode
                throw "The Windows Desktop Runtime installer failed with exit code $ExitCode. See $BundleLogFile."
            }

            if (-not (Test-TargetRuntimeInstalled -Inventory (Get-DotNetInventory) -Release $Release)) {
                Write-Log "Runtime verification failed after installation. Running installer repair once..."
                $RepairExitCode = Invoke-DesktopRuntimeBundle -InstallerPath $InstallerPath -Action repair

                if ($SuccessExitCodes -notcontains $RepairExitCode) {
                    $script:FailureExitCode = $RepairExitCode
                    throw "The Windows Desktop Runtime repair failed with exit code $RepairExitCode. See $BundleLogFile."
                }

                if (-not (Test-TargetRuntimeInstalled -Inventory (Get-DotNetInventory) -Release $Release)) {
                    throw "The .NET 10 runtimes are still not usable and registered after repair."
                }

                if ($RepairExitCode -ne 0) {
                    $ExitCode = $RepairExitCode
                }
            }
        }
        finally {
            if (Test-Path $DownloadDir) {
                Remove-Item -Path $DownloadDir -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "Temporary download directory removed."
            }
        }
    }

    Write-Log "Verified .NET host starts and both .NET 10 runtime families are installed and registered."
    Write-InventoryLog -Label "Runtime inventory after installation" -Inventory (Get-DotNetInventory)

    if (-not $PreExisting -or -not (Test-Path $ManifestFile)) {
        $Manifest = [ordered]@{
            InstalledAt           = Get-Date -Format 'o'
            DesktopRuntimeVersion = $Release.DesktopVersion.ToString()
            CoreRuntimeVersion    = $Release.CoreVersion.ToString()
            InstallerUrl          = $Release.Url
            InstallerSha512       = $Release.Sha512
            PreExisting           = $PreExisting
        }

        $Manifest | ConvertTo-Json | Set-Content -Path $ManifestFile -Encoding utf8
        Write-Log "Runtime ownership manifest written: $ManifestFile (PreExisting=$PreExisting)"
    }

    if ($ExitCode -eq 3010 -or $ExitCode -eq 1641) {
        Write-Log "A restart is required to complete the installation."
    }

    Write-Log "=========================================="
    Write-Log ".NET 10 Desktop Runtime installation completed"
    Write-Log "=========================================="

    exit $ExitCode
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Log "Installation failed."

    exit $script:FailureExitCode
}
