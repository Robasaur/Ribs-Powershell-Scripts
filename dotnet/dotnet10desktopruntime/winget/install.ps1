$ErrorActionPreference = 'Stop'

$logRoot = Join-Path $env:ProgramData 'IntuneLogs'
$logPath = Join-Path $logRoot 'WinGet-Prereq.log'

New-Item -Path $logRoot -ItemType Directory -Force | Out-Null

function Write-Log {
    param([Parameter(Mandatory)][string]$Message)

    Add-Content -Path $logPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
}

function Test-WinGetProvisioned {
    $provisioned = Get-AppxProvisionedPackage -Online |
        Where-Object { $_.DisplayName -eq 'Microsoft.DesktopAppInstaller' }
    if ($provisioned) {
        return $true
    }

    $installed = Get-AppxPackage -AllUsers -Name Microsoft.DesktopAppInstaller
    return [bool]$installed
}

function Get-DeviceArchitecture {
    $architecture = if ($env:PROCESSOR_ARCHITEW6432) {
        $env:PROCESSOR_ARCHITEW6432
    }
    else {
        $env:PROCESSOR_ARCHITECTURE
    }

    switch ($architecture.ToUpperInvariant()) {
        'AMD64' { return 'x64' }
        'ARM64' { return 'arm64' }
        'X86' { return 'x86' }
        default { throw "Unsupported processor architecture: $architecture" }
    }
}

$downloadRoot = Join-Path $env:TEMP ("WinGet-Intune-" + [guid]::NewGuid())

try {
    Write-Log 'Starting WinGet prerequisite installation.'

    if (Test-WinGetProvisioned) {
        Write-Log 'App Installer is already installed or provisioned.'
        exit 0
    }

    $architecture = Get-DeviceArchitecture
    $xamlArchitecture = switch ($architecture) {
        'x64' { 'x64' }
        'arm64' { 'arm64' }
        'x86' { 'x86' }
    }

    $urls = @{
        AppInstaller = 'https://aka.ms/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
        VCLibs       = "https://aka.ms/Microsoft.VCLibs.$xamlArchitecture.14.00.Desktop.appx"
        'UI.Xaml'    = "https://aka.ms/Microsoft.UI.Xaml.2.8.$xamlArchitecture.appx"
    }

    New-Item -Path $downloadRoot -ItemType Directory -Force | Out-Null
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $appInstallerPath = Join-Path $downloadRoot 'Microsoft.DesktopAppInstaller.msixbundle'
    $vcLibsPath = Join-Path $downloadRoot 'Microsoft.VCLibs.appx'
    $uiXamlPath = Join-Path $downloadRoot 'Microsoft.UI.Xaml.appx'

    foreach ($download in @(
        @{ Name = 'App Installer'; Uri = $urls.AppInstaller; Path = $appInstallerPath }
        @{ Name = 'Microsoft VCLibs'; Uri = $urls.VCLibs; Path = $vcLibsPath }
        @{ Name = 'Microsoft UI.Xaml'; Uri = $urls.'UI.Xaml'; Path = $uiXamlPath }
    )) {
        Write-Log "Downloading $($download.Name) from $($download.Uri)"
        Invoke-WebRequest -Uri $download.Uri -OutFile $download.Path -UseBasicParsing
        if (-not (Test-Path -LiteralPath $download.Path -PathType Leaf) -or (Get-Item -LiteralPath $download.Path).Length -eq 0) {
            throw "The $($download.Name) download was empty or missing."
        }
    }

    Write-Log "Provisioning App Installer for all users (architecture: $architecture)."
    Add-AppxProvisionedPackage -Online `
        -PackagePath $appInstallerPath `
        -DependencyPackagePath @($vcLibsPath, $uiXamlPath) `
        -SkipLicense | Out-Null

    if (-not (Test-WinGetProvisioned)) {
        throw 'App Installer provisioning completed, but the package was not detected.'
    }

    Write-Log 'App Installer provisioning succeeded.'
    exit 0
}
catch {
    Write-Log "Installation failed: $($_.Exception.Message)"
    Write-Error $_ -ErrorAction Continue
    exit 1
}
finally {
    if (Test-Path -LiteralPath $downloadRoot) {
        try {
            Remove-Item -LiteralPath $downloadRoot -Recurse -Force
        }
        catch {
            Write-Log "Warning: could not remove temporary downloads: $($_.Exception.Message)"
        }
    }
}
