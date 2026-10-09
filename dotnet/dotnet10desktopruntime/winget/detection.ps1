$ErrorActionPreference = 'Stop'

$detected = $false

try {
    $installed = Get-AppxPackage -Name Microsoft.DesktopAppInstaller
    if ($installed) {
        $detected = $true
    }
}
catch {
    Write-Output "Could not query the current user's App Installer package: $($_.Exception.Message)"
}

if (-not $detected) {
    try {
        $installedForAnyUser = Get-AppxPackage -AllUsers -Name Microsoft.DesktopAppInstaller
        $detected = [bool]$installedForAnyUser
    }
    catch {
        Write-Output "Could not query App Installer packages for all users: $($_.Exception.Message)"
    }
}

if (-not $detected) {
    try {
        $provisioned = Get-AppxProvisionedPackage -Online |
            Where-Object { $_.DisplayName -eq 'Microsoft.DesktopAppInstaller' }
        $detected = [bool]$provisioned
    }
    catch {
        Write-Output "Could not query provisioned App Installer packages: $($_.Exception.Message)"
    }
}

if ($detected) {
    Write-Output 'WinGet/App Installer detected.'
    exit 0
}

Write-Output 'WinGet/App Installer not detected.'
exit 1
