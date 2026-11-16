# medium.ps1 defines Medium, which starts a command at medium integrity, and AtMedium, which runs one
# command line that way and returns its output. The workflow runs elevated, as the hosted runner does,
# so a probe at medium integrity sees the runner's windows outrank it as an elevated app outranks a
# standard Moorings.

Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

// Medium starts a command with a copy of this process's token lowered to medium integrity,
// so windows of the runner's high integrity processes outrank it as an elevated app does.
public static class Medium {
    [StructLayout(LayoutKind.Sequential)]
    struct SidAndAttributes { public IntPtr Sid; public uint Attributes; }
    [StructLayout(LayoutKind.Sequential)]
    struct MandatoryLabel { public SidAndAttributes Label; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct StartupInfo {
        public int cb; public string reserved, desktop, title;
        public int x, y, xSize, ySize, xChars, yChars, fill, flags;
        public short show, reserved2; public IntPtr reserved3, stdIn, stdOut, stdErr;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct ProcessInfo { public IntPtr process, thread; public int pid, tid; }

    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32.dll")] static extern bool GetExitCodeProcess(IntPtr h, out uint code);
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool DuplicateTokenEx(IntPtr token, uint access, IntPtr attrs, int level, int type, out IntPtr dup);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool ConvertStringSidToSid(string sid, out IntPtr psid);
    [DllImport("advapi32.dll")] static extern int GetLengthSid(IntPtr sid);
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool SetTokenInformation(IntPtr token, int cls, ref MandatoryLabel info, int length);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcessAsUser(IntPtr token, string app, string cmd, IntPtr pa, IntPtr ta,
        bool inherit, uint flags, IntPtr env, string dir, ref StartupInfo si, out ProcessInfo pi);

    // Run starts cmd at medium integrity, waits up to ms, and returns its exit code.
    public static uint Run(string cmd, uint ms) {
        IntPtr token, dup, sid;
        if (!OpenProcessToken(GetCurrentProcess(), 0xF01FF, out token)) throw new Win32Exception();
        if (!DuplicateTokenEx(token, 0xF01FF, IntPtr.Zero, 2, 1, out dup)) throw new Win32Exception();
        if (!ConvertStringSidToSid("S-1-16-8192", out sid)) throw new Win32Exception();
        var label = new MandatoryLabel();
        label.Label.Sid = sid;
        label.Label.Attributes = 0x20;
        if (!SetTokenInformation(dup, 25, ref label, Marshal.SizeOf(label) + GetLengthSid(sid))) throw new Win32Exception();
        var si = new StartupInfo();
        si.cb = Marshal.SizeOf(si);
        ProcessInfo pi;
        if (!CreateProcessAsUser(dup, null, cmd, IntPtr.Zero, IntPtr.Zero, false, 0, IntPtr.Zero, null, ref si, out pi)) throw new Win32Exception();
        if (WaitForSingleObject(pi.process, ms) != 0) throw new TimeoutException("medium run did not finish");
        uint code;
        GetExitCodeProcess(pi.process, out code);
        return code;
    }
}
'@

# AtMedium runs line through cmd at medium integrity with its output in RUNNER_TEMP\name.txt, waits up
# to ms, and returns the output lines and the exit code.
function AtMedium([string] $name, [string] $line, [uint32] $ms) {
  $log = Join-Path $env:RUNNER_TEMP "$name.txt"
  $cmd = Join-Path $env:RUNNER_TEMP "$name.cmd"
  Set-Content $cmd -Encoding ascii -Value @('@echo off', "$line > `"$log`" 2>&1")
  $code = [Medium]::Run("cmd.exe /c `"$cmd`"", $ms)
  [pscustomobject]@{ Lines = @(Get-Content $log); Code = [int]$code }
}
