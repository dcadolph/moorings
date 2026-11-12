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
every other window in the channel between them. With no ultrawide attached it anchors on
your widest display: one side takes half, and both sides take a third each when the display
is at least 1920 wide at its scale. On a narrower display the right side waits in the
channel, and a banner says so.

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
- AltGr: on a layout with AltGr, such as German or Polish, AltGr still types its
  characters (AltGr+E is the euro sign in German). Hold left Ctrl with left Alt for the
  shortcut: a macro tool that sends the whole chord at once types the character instead.
  A window run as administrator is the exception: Windows drops what Moorings types into
  it, so the character is lost there. A shortcut on a key that AltGr makes a dead key is
  left unbound. Save a report lists both.
- Widths: on an ultrawide, pick the strip widths from the tray menu.
- Custom sizes: sizes added under "sizes" in the settings file show in the Custom sizes
  folder of the tray menu. A shortcut set for "show-menu" opens the tray menu at the
  pointer.
- Organize, in the tray menu, tiles the free windows in columns, rows or a grid, cascades
  them, cycles through windows stacked on one spot, and mirrors them across the channel.
  Channel fits every channel window in at once and lines up the front two or three side by
  side. Undo tidy puts them all back. Each runs on the window that was in front.
- Stack badge: with "stacking": {"badge": true} in the settings file, resting the pointer
  on the corner of stacked windows shows how many there are.
- Tiling, in the tray menu, keeps the free windows of each display in a tall, wide,
  columns, rows or BSP layout as windows open and close. A window you drag or resize
  floats until you choose a layout again. Grow main and Shrink main change the main
  pane's share in the tall and wide layouts.
- Workspaces, in the tray menu: Save workspace keeps where every free window sits, and
  Recall puts them back. Recall with these displays brings a workspace back by itself when
  the same monitors are plugged in again. Open apps that are not running starts the apps a
  recall finds missing and places their windows once they show.
- App rules: in the settings file, "appRules": [{"bundle": "C:\\Windows\\System32\\notepad.exe",
  "action": "left-half"}] places an app's first window each time the app starts, by an
  action or by a "frame".
- Pause stops everything until you choose it again. Launch at login starts Moorings when
  you sign in.

Links and the command line

- A link such as moorings://action?name=left-half runs that action on the window in front,
  and starts Moorings first if it is not running. Moorings registers the moorings: scheme
  for your user each time it starts. To remove it, delete HKEY_CURRENT_USER\Software\Classes\moorings.
- MooringsWin.exe --action left-half does the same from a terminal, and prints not running
  if Moorings is not running. It returns right away in a terminal. To read its exit code in
  PowerShell, pipe it: .\MooringsWin.exe --action left-half | Write-Output. In a script,
  use Start-Process -Wait -PassThru.
- Links and --action never close windows. Those actions run only from shortcuts and the menu.

Mouse buttons and caption buttons

- In the settings file, mouseButtons binds a button number to an action: 2 is the middle
  button, 3 is back and 4 is forward, as in "mouseButtons": {"3": "left-half"}.
- buttonClicks binds a click on a window's own button: green is maximize, yellow is minimize
  and red is close, plain or with +shift, +option for Alt, or +command for the Windows key,
  as in "buttonClicks": {"green+shift": "left-half"}.
- A bound click runs the action on that window and never reaches the button. An unbound
  click works as usual. Some apps draw their own title bar and do not name these buttons to
  Windows. Those apps keep their usual clicks.

This build is checked on GitHub's Windows runner, not yet on a physical ultrawide.

Moorings keeps a log in %LOCALAPPDATA%\Moorings\moorings.log, with one older file beside
it, so the two never pass 2 MB. Save a report in the tray menu writes one text file to
your desktop with the version, your monitors, the shortcuts it gave up and why, your
settings, and the end of the log, and opens the folder with the file selected. That file
is the one to send back.

Settings live in %APPDATA%\Moorings\choices.json. Open settings file in the tray menu
opens it, and Moorings reads it again when it changes or on Reload settings. To quit,
choose Quit Moorings from the tray menu.
'@
Write-Host "packaged $Name in $dir"
if ($env:GITHUB_OUTPUT) {
  "name=$Name" | Add-Content -Path $env:GITHUB_OUTPUT
  "dir=$dir" | Add-Content -Path $env:GITHUB_OUTPUT
}
