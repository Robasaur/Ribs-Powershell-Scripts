$ErrorActionPreference = 'Stop'

$logRoot = Join-Path $env:ProgramData 'IntuneLogs'
$logPath = Join-Path $logRoot 'WinGet-Prereq.log'

New-Item -Path $logRoot -ItemType Directory -Force | Out-Null

function Write-Log {
    param([Parameter(Mandatory)][string]$Message)

    Add-Content -Path $logPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
}

try {
    Write-Log 'Starting device-wide App Installer/WinGet removal.'

    $installedPackages = @(Get-AppxPackage -AllUsers -Name Microsoft.DesktopAppInstaller)
    foreach ($package in $installedPackages) {
        Write-Log "Removing installed package $($package.PackageFullName) for all users."
        Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop
    }

    $provisionedPackages = @(
        Get-AppxProvisionedPackage -Online |
            Where-Object { $_.DisplayName -eq 'Microsoft.DesktopAppInstaller' }
    )
    foreach ($package in $provisionedPackages) {
        Write-Log "Removing provisioned package $($package.PackageName)."
        Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -AllUsers -ErrorAction Stop |
            Out-Null
    }

    $remainingInstalled = @(Get-AppxPackage -AllUsers -Name Microsoft.DesktopAppInstaller)
    $remainingProvisioned = @(
        Get-AppxProvisionedPackage -Online |
            Where-Object { $_.DisplayName -eq 'Microsoft.DesktopAppInstaller' }
    )
    if ($remainingInstalled.Count -gt 0 -or $remainingProvisioned.Count -gt 0) {
        throw 'App Installer remains installed for one or more users or provisioned on the device.'
    }

    Write-Log 'App Installer/WinGet was removed for all users and is no longer provisioned.'
    exit 0
}
catch {
    Write-Log "Uninstallation failed: $($_.Exception.Message)"
    Write-Error $_ -ErrorAction Continue
    exit 1
}
