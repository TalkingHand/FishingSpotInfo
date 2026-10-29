# Real mouse clicks for the in-game test (tests/tools/uitest.sh starts this next to `pzt run`).
# The test Lua writes Zomboid/Lua/fsi_click_req.txt = "<id> <left|right> <x> <y> <screenW> <screenH>"
# (pixels in getCore():getScreenWidth/Height space, scaled to the window client size); this clicks there
# with the real mouse (the cursor moves, then goes back) and
# writes fsi_click_done.txt = "<id> <ok|error text>". Only the test game of this project is
# touched: the ProjectZomboid64.exe whose command line has this project's -cachedir.
# Exits when that game is gone (after it was seen) or after $TimeoutSec.
param([string]$EnvDir, [int]$TimeoutSec = 900)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class FsiInput {
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint f, UIntPtr e);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L; public int T; public int R; public int B; }
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@

# physical pixels everywhere: without this, Windows display scaling (125% here) maps the client
# point and the cursor through a scale the DPI-aware game does not use
[void][FsiInput]::SetProcessDPIAware()

$luaDir = Join-Path $EnvDir "Zomboid\Lua"
$req = Join-Path $luaDir "fsi_click_req.txt"
$done = Join-Path $luaDir "fsi_click_done.txt"
$cacheDir = (Join-Path $EnvDir "Zomboid")
Remove-Item $req, $done -ErrorAction SilentlyContinue

function Find-Game {
    Get-CimInstance Win32_Process -Filter "Name='ProjectZomboid64.exe'" |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains("-cachedir=$cacheDir") } |
        Select-Object -First 1
}

$start = Get-Date
$seen = $false
$lastId = ""
while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSec) {
    $game = Find-Game
    if ($game) { $seen = $true } elseif ($seen) { break }
    if ($game -and (Test-Path $req)) {
        $line = (Get-Content $req -TotalCount 1 -ErrorAction SilentlyContinue)
        if ($line) {
            $parts = $line.Trim() -split '\s+'
            if ($parts.Count -eq 6 -and $parts[0] -ne $lastId) {
                $lastId = $parts[0]
                $result = "ok"
                try {
                    $hwnd = (Get-Process -Id $game.ProcessId).MainWindowHandle
                    if ($hwnd -eq [IntPtr]::Zero) { throw "no game window" }
                    $old = New-Object FsiInput+POINT
                    [void][FsiInput]::GetCursorPos([ref]$old)
                    if ([FsiInput]::GetForegroundWindow() -ne $hwnd) {
                        # ALT tap lets a background process take the foreground. Only while the
                        # game is not in front: a lone ALT in the game window opens the window
                        # menu mode, which eats the next click
                        [FsiInput]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
                        [FsiInput]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
                        [void][FsiInput]::ShowWindow($hwnd, 9)
                        [void][FsiInput]::SetForegroundWindow($hwnd)
                        Start-Sleep -Milliseconds 200
                    }
                    if ([FsiInput]::GetForegroundWindow() -ne $hwnd) { throw "game window not in front" }
                    $rc = New-Object FsiInput+RECT
                    [void][FsiInput]::GetClientRect($hwnd, [ref]$rc)
                    $sx = ($rc.R - $rc.L) / [double]$parts[4]; $sy = ($rc.B - $rc.T) / [double]$parts[5]
                    $p = New-Object FsiInput+POINT
                    $p.X = [int]([double]$parts[2] * $sx); $p.Y = [int]([double]$parts[3] * $sy)
                    [void][FsiInput]::ClientToScreen($hwnd, [ref]$p)
                    [void][FsiInput]::SetCursorPos($p.X, $p.Y)
                    Start-Sleep -Milliseconds 300
                    if ($parts[1] -eq "right") { $down = 0x0008; $up = 0x0010 } else { $down = 0x0002; $up = 0x0004 }
                    [FsiInput]::mouse_event($down, 0, 0, 0, [UIntPtr]::Zero)
                    Start-Sleep -Milliseconds 80
                    [FsiInput]::mouse_event($up, 0, 0, 0, [UIntPtr]::Zero)
                    Start-Sleep -Milliseconds 300
                    [void][FsiInput]::SetCursorPos($old.X, $old.Y)
                    $result = "ok screen $($p.X),$($p.Y) scale $sx"
                } catch {
                    $result = "error $($_.Exception.Message)"
                }
                Set-Content -Path $done -Value "$lastId $result" -Encoding ascii
                Write-Output "[clicker] $line -> $result"
            }
        }
    }
    Start-Sleep -Milliseconds 200
}
Write-Output "[clicker] exit"
