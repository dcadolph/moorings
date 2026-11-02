# Build the release exe and gather it with the Swift runtime DLLs and the read-me into one folder,
# the folder the Windows zip holds. The windows workflow packages every run with it, and the release
# workflow stamps the tag's version first.
#
# Usage: package.ps1 -Name <folder name> [-Version <x.y.z>]
# Run from windows/. Writes name=<folder name> and dir=<full path> to GITHUB_OUTPUT when it is set.
param(
  [Parameter(Mandatory = $true)] [string] $Name,
  [string] $Version = ''
)
$ErrorActionPreference = 'Stop'

if ($Version -ne '') {
  if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "version $Version is not x.y.z" }
  $file = Join-Path $PSScriptRoot 'Sources/MooringsWin/App/Version.swift'
  $text = Get-Content -Raw $file
  $stamped = $text -replace 'let version = "dev"', "let version = `"$Version`""
  if ($stamped -eq $text) { throw "Version.swift does not hold the dev version" }
  Set-Content -Path $file -Value $stamped -NoNewline -Encoding utf8
}

swift build -c release -Xswiftc -warnings-as-errors | Out-Host
if ($LASTEXITCODE -ne 0) { throw "release build failed" }
$bin = swift build -c release -Xswiftc -warnings-as-errors --show-bin-path
$runtime = Split-Path (where.exe swiftCore.dll | Select-Object -First 1)
$dir = Join-Path $env:RUNNER_TEMP $Name
New-Item -ItemType Directory -Path $dir | Out-Null
Copy-Item (Join-Path $bin 'MooringsWin.exe') $dir
Copy-Item (Join-Path $runtime '*.dll') $dir
foreach ($dll in 'vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll') {
  $path = Join-Path $env:SystemRoot "System32\$dll"
  if (Test-Path $path) { Copy-Item $path $dir }
}
Set-Content -Path (Join-Path $dir 'README-windows.txt') -Encoding utf8 -Value @'
Moorings for Windows, early build

Moorings holds apps in the side strips of an ultrawide monitor, 21:9 or wider, and keeps
every other window in the channel between them.

Run it

1. Unzip this folder anywhere, for example Documents\Moorings. Keep the files together:
   MooringsWin.exe runs on the DLLs beside it.
2. Double-click MooringsWin.exe. This build is not signed yet, so Windows SmartScreen may
   say it protected your PC. Click More info, then Run anyway. It asks once.
3. Moorings has no window. Its icon sits in the notification area at the right end of the
   taskbar. Click the up arrow there if it is hidden, then click the icon for the menu.

What it does

- Slots: in the tray menu, choose an app for Left top, Left bottom, Right top or Right
  bottom. Moorings holds its window in that strip.
- Any other window that lands on a strip is pushed back into the channel.
- Moving a held window by hand releases it. Ctrl+Alt+Backspace on it puts it back.
- Window shortcuts from Rectangle: Ctrl+Alt+Left and Right for halves, Ctrl+Alt+U, I, J
  and K for quarters, Ctrl+Alt+D, F and G for thirds, Ctrl+Alt+Enter to maximize and
  Ctrl+Alt+C to center, all inside the channel. On a held window Ctrl+Alt+Enter lifts it
  over the channel, and pressing it again lowers it.
- Widths: pick the strip widths from the tray menu.
- Pause stops everything until you choose it again. Launch at login starts Moorings when
  you sign in.

This build is checked on GitHub's Windows runner and in a Windows 11 virtual machine at
3440x1440, not yet on a physical ultrawide.

Settings live in %APPDATA%\Moorings\choices.json. Open settings file in the tray menu
opens it, and Moorings reads it again when it changes or on Reload settings. To quit,
choose Quit Moorings from the tray menu.
'@
Write-Host "packaged $Name in $dir"
if ($env:GITHUB_OUTPUT) {
  "name=$Name" | Add-Content -Path $env:GITHUB_OUTPUT
  "dir=$dir" | Add-Content -Path $env:GITHUB_OUTPUT
}
