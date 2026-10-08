<#
_author_  = Rob Plumridge
_version_ = 6
_purpose_ = Intune Win32 detection for .NET 10 Desktop Runtime 10.0.12+ (x64)
#>

$ProgramFiles64 = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
$DotnetExe = Join-Path $ProgramFiles64 "dotnet\dotnet.exe"
$SharedFxRegistryRoot = "HKLM:\SOFTWARE\WOW6432Node\dotnet\Setup\InstalledVersions\x64\sharedfx"
$RequiredVersion = [version]"10.0.12"

function Found {
    param (
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Output $Message
    exit 0
}

function NotFound {
    param (
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Output $Message
    exit 1
}

function Get-RegisteredVersions {
    param (
        [Parameter(Mandatory)]
        [string]$Family
    )

    $FamilyKey = Get-Item -Path (Join-Path $SharedFxRegistryRoot $Family) -ErrorAction SilentlyContinue

    if ($FamilyKey) {
        $FamilyKey.GetValueNames()
    }
}

function Get-UsableVersions {
    param (
        [Parameter(Mandatory)]
        [string]$Family,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$HostOutput
    )

    $RegisteredVersions = @(Get-RegisteredVersions -Family $Family)

    foreach ($Line in $HostOutput) {
        if ("$Line" -match "^$([regex]::Escape($Family))\s+(\d+\.\d+\.\d+)\s") {
            $RuntimeVersion = [version]$Matches[1]

            if ($RuntimeVersion -ge $RequiredVersion -and $RegisteredVersions -contains $RuntimeVersion.ToString()) {
                $RuntimeVersion
            }
        }
    }
}

try {
    if (-not (Test-Path $DotnetExe)) {
        NotFound ".NET runtime not detected - dotnet.exe is missing"
    }

    $HostOutput = @(& $DotnetExe --list-runtimes 2>&1)

    if ($LASTEXITCODE -ne 0) {
        $HostError = ($HostOutput | Select-Object -Last 1 | ForEach-Object { "$_".Trim() })
        NotFound "Unable to query installed .NET runtimes: $HostError"
    }

    if (-not $HostOutput) {
        NotFound "No .NET runtimes were returned by dotnet.exe"
    }

    $DesktopVersions = @(Get-UsableVersions -Family "Microsoft.WindowsDesktop.App" -HostOutput $HostOutput)
    $CoreVersions = @(Get-UsableVersions -Family "Microsoft.NETCore.App" -HostOutput $HostOutput)

    if (-not $DesktopVersions -or -not $CoreVersions) {
        NotFound ".NET 10 Desktop Runtime is incomplete: Microsoft.WindowsDesktop.App and Microsoft.NETCore.App $RequiredVersion+ must both be installed and registered"
    }

    $Versions = $DesktopVersions | Sort-Object -Descending -Unique | ForEach-Object { $_.ToString() }
    Found ".NET 10 Desktop Runtime detected: $($Versions -join ', ')"
}
catch {
    NotFound "Unable to query installed .NET runtimes: $($_.Exception.Message)"
}
