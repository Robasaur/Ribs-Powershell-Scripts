<#
_author_  = Rob Plumridge
_version_ = 4
_purpose_ = Intune Win32 detection for any .NET 8.0 SDK (x64)
#>

$DotnetExe = Join-Path $env:ProgramFiles "dotnet\dotnet.exe"

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

if (-not (Test-Path $DotnetExe)) {
    NotFound ".NET SDK not detected - dotnet.exe not found"
}

try {
    $SDKs = & $DotnetExe --list-sdks 2>$null

    if ($LASTEXITCODE -ne 0) {
        NotFound "Unable to query installed .NET SDKs"
    }

    if (-not $SDKs) {
        NotFound "No .NET SDKs detected"
    }

    $DotNet8SDKs = $SDKs |
        Where-Object {
            $_ -match '^8\.0\.\d+\s'
        }

    if ($DotNet8SDKs) {
        $Versions = foreach ($SDK in $DotNet8SDKs) {
            if ($SDK -match '^(\d+\.\d+\.\d+)\s') {
                $Matches[1]
            }
        }

        Found ".NET 8 SDK detected: $($Versions -join ', ')"
    }

    NotFound ".NET 8 SDK not detected"
}
catch {
    NotFound "Unable to query installed .NET SDKs"
}