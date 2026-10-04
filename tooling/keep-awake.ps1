param([Parameter(Mandatory=$true)][string]$StopFile,
      [Parameter(Mandatory=$true)][string]$StatusFile)
$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class EngramWakeRequest {
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern uint SetThreadExecutionState(uint flags);
}
'@
try {
    if ([EngramWakeRequest]::SetThreadExecutionState([uint32]2147483649) -eq 0) { throw 'Unable to request system wakefulness.' }
    [IO.File]::WriteAllText($StatusFile, "active:$PID")
    while (-not (Test-Path -LiteralPath $StopFile)) { Start-Sleep -Seconds 2 }
} finally {
    [void][EngramWakeRequest]::SetThreadExecutionState([uint32]2147483648)
    [IO.File]::WriteAllText($StatusFile, "stopped:$PID")
}
