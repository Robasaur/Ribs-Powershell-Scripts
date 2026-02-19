$ErrorActionPreference = "Stop"
$DestDir  = "C:\Intune"
$Files    = @(
  "", #wallpaper
  "" #lockscreen
)

# Source
$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Check destination folder exists
if (-not (Test-Path -LiteralPath $DestDir)) {
  New-Item -Path $DestDir -ItemType Directory -Force | Out-Null
}

# Copy files
foreach ($f in $Files) {
  $src = Join-Path $SourceDir $f
  $dst = Join-Path $DestDir  $f

  if (-not (Test-Path -LiteralPath $src)) {
    throw "Missing source file: $src"
  }

  Copy-Item -LiteralPath $src -Destination $dst -Force
}

exit 0