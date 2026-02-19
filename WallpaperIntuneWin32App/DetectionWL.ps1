if (
  (Test-Path -LiteralPath "") -and #this can just be 1 or multiple files just extend the -and
  (Test-Path -LiteralPath "")
) { exit 0 }

exit 1