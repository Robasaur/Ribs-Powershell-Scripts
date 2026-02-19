$ErrorActionPreference = "Stop"
$DestDir  = "C:\Intune"
$Files    = @(
  "", #wallpaper
  "" #lockscreen
)

foreach ($f in $Files) {
  $path = Join-Path $DestDir $f
  if (Test-Path -LiteralPath $path) {
    Remove-Item -LiteralPath $path -Force
  }
}

# remove folder If folder is empty
if (Test-Path -LiteralPath $DestDir) {
  $remaining = Get-ChildItem -LiteralPath $DestDir -Force -ErrorAction SilentlyContinue
  if (-not $remaining) {
    Remove-Item -LiteralPath $DestDir -Force
  }
}

exit 0