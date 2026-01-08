[CmdletBinding()]
param(
  [string]$InputJson,
  [string]$OutputHtml
)

# UI helpers
function Select-OpenFile {
  param(
    [string]$Title = "Select a file",
    [string]$Filter = "All files (*.*)|*.*",
    [string]$InitialDirectory = $env:USERPROFILE
  )

  Add-Type -AssemblyName System.Windows.Forms | Out-Null
  $dlg = New-Object System.Windows.Forms.OpenFileDialog
  $dlg.Title = $Title
  $dlg.Filter = $Filter
  $dlg.InitialDirectory = $InitialDirectory
  $dlg.Multiselect = $false

  if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
    throw "Cancelled file selection."
  }
  return $dlg.FileName
}

function Select-SaveFile {
  param(
    [string]$Title = "Save file as",
    [string]$Filter = "All files (*.*)|*.*",
    [string]$InitialDirectory = $env:USERPROFILE,
    [string]$DefaultFileName = "Bookmarks.html"
  )

  Add-Type -AssemblyName System.Windows.Forms | Out-Null
  $dlg = New-Object System.Windows.Forms.SaveFileDialog
  $dlg.Title = $Title
  $dlg.Filter = $Filter
  $dlg.InitialDirectory = $InitialDirectory
  $dlg.FileName = $DefaultFileName
  $dlg.OverwritePrompt = $true

  if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
    throw "Cancelled save selection."
  }
  return $dlg.FileName
}

# If params missing, prompt with file dialogs
if (-not $InputJson) {
  $InputJson = Select-OpenFile `
    -Title "Select Edge/Chrome Bookmarks JSON file" `
    -Filter "Bookmarks JSON (Bookmarks; *.json)|Bookmarks;*.json|All files (*.*)|*.*" `
    -InitialDirectory "$env:LOCALAPPDATA"
}

if (-not $OutputHtml) {
  $OutputHtml = Select-SaveFile `
    -Title "Save exported bookmarks HTML" `
    -Filter "HTML file (*.html)|*.html|All files (*.*)|*.*" `
    -InitialDirectory ([System.IO.Path]::GetDirectoryName($InputJson)) `
    -DefaultFileName "Bookmarks.html"
}

if (!(Test-Path -LiteralPath $InputJson)) {
  throw "InputJson not found: $InputJson"
}

# Read + parse JSON
$jsonText = Get-Content -Raw -LiteralPath $InputJson
$bm = $jsonText | ConvertFrom-Json

# Basic HTML escaping
function Escape-Html([string]$s) {
  if ($null -eq $s) { return "" }
  return ($s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;')
}

# Convert Chrome/Edge "date_added" (microseconds since 1601-01-01 UTC) to Unix seconds for ADD_DATE
function ChromeTimeToUnixSeconds($chromeTime) {
  if ($null -eq $chromeTime -or $chromeTime -eq "") { return $null }
  try {
    $us = [double]$chromeTime
    $dt = [datetime]::SpecifyKind([datetime]"1601-01-01T00:00:00Z",[System.DateTimeKind]::Utc).AddMilliseconds($us / 1000.0)
    $unix = [int][math]::Floor(($dt - [datetime]"1970-01-01T00:00:00Z").TotalSeconds)
    return $unix
  } catch { return $null }
}

# Build HTML using a StringBuilder
$sb = New-Object System.Text.StringBuilder

# Netscape bookmark file header (what browsers expect)
[void]$sb.AppendLine('<!DOCTYPE NETSCAPE-Bookmark-file-1>')
[void]$sb.AppendLine('<!-- This is an automatically generated file. -->')
[void]$sb.AppendLine('<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">')
[void]$sb.AppendLine('<TITLE>Bookmarks</TITLE>')
[void]$sb.AppendLine('<H1>Bookmarks</H1>')
[void]$sb.AppendLine('<DL><p>')

function Write-Node($node, [int]$indent = 1) {
  $pad = ("  " * $indent)

  if ($node.type -eq "folder") {
    $name = Escape-Html $node.name
    $add  = ChromeTimeToUnixSeconds $node.date_added
    $attr = ""
    if ($add) { $attr = " ADD_DATE=`"$add`"" }

    [void]$sb.AppendLine("${pad}<DT><H3$attr>$name</H3>")
    [void]$sb.AppendLine("${pad}<DL><p>")

    foreach ($child in ($node.children | Where-Object { $_ -ne $null })) {
      Write-Node $child ($indent + 1)
    }

    [void]$sb.AppendLine("${pad}</DL><p>")
  }
  elseif ($node.type -eq "url") {
    $name = Escape-Html $node.name
    $url  = Escape-Html $node.url
    $add  = ChromeTimeToUnixSeconds $node.date_added

    $attr = " HREF=`"$url`""
    if ($add) { $attr += " ADD_DATE=`"$add`"" }

    [void]$sb.AppendLine("${pad}<DT><A$attr>$name</A>")
  }
}

# Roots
$roots = @("bookmark_bar","other","synced")

foreach ($r in $roots) {
  $rootNode = $bm.roots.$r
  if ($null -ne $rootNode) {
    $wrapper = [pscustomobject]@{
      type       = "folder"
      name       = $rootNode.name
      date_added = $rootNode.date_added
      children   = $rootNode.children
    }
    Write-Node $wrapper 1
  }
}

[void]$sb.AppendLine('</DL><p>')

# Write output
$sb.ToString() | Set-Content -LiteralPath $OutputHtml -Encoding UTF8

Write-Host "Done!"
Write-Host "Input : $InputJson"
Write-Host "Output: $OutputHtml"