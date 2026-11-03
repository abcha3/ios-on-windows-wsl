# ============================================================================
#  relay-setup.ps1
#  ---------------------------------------------------------------------------
#  Build the TCP bridge to Apple's usbmuxd so WSL can install apps.
#
#  ASCII-ONLY on purpose: Windows PowerShell 5.1 reads .ps1 as ANSI (GBK on a
#  Chinese system), so non-ASCII text truncates string literals and the script
#  fails with "The string is missing the terminator".
#
#  The bridge MUST NOT use port 27015 - Apple's service binds 127.0.0.1:27015
#  and an 0.0.0.0 listener on the same port prevents it from starting
#  (symptom: "Waiting for service ... to start" forever).
# ============================================================================
$ErrorActionPreference = 'Continue'

$LISTEN_PORT = 27016
$APPLE_PORT  = 27015

Write-Host "=== 1. Apple Mobile Device Support present? ===" -ForegroundColor Cyan
$svc = Get-Service | Where-Object { $_.DisplayName -like '*Apple Mobile*' } | Select-Object -First 1
if (-not $svc) {
  Write-Host "  NOT INSTALLED" -ForegroundColor Red
  Write-Host "  run: winget install --id Apple.AppleMobileDeviceSupport"
  exit 1
}
Write-Host ("  " + $svc.Name + " = " + $svc.Status)

Write-Host "=== 2. remove any listener squatting on $APPLE_PORT ===" -ForegroundColor Cyan
$existing = netsh interface portproxy show v4tov4 2>&1 | Out-String
if ($existing -match "$APPLE_PORT\s") {
  netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=$APPLE_PORT 2>&1 | Out-Null
  Write-Host "  removed conflicting portproxy on $APPLE_PORT"
}

Write-Host "=== 3. start Apple service ===" -ForegroundColor Cyan
if ($svc.Status -ne 'Running') {
  sc.exe start "$($svc.Name)" | Out-Null
  for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Seconds 1
    if ((Get-Service $svc.Name).Status -eq 'Running') { break }
  }
}
$st = (Get-Service $svc.Name).Status
Write-Host ("  status: " + $st)
if ($st -ne 'Running') {
  Write-Host "  still not running. Check nothing else holds $APPLE_PORT." -ForegroundColor Yellow
}

Write-Host "=== 4. who listens on $APPLE_PORT ===" -ForegroundColor Cyan
$c = Get-NetTCPConnection -LocalPort $APPLE_PORT -State Listen -ErrorAction SilentlyContinue
if ($c) {
  $c | ForEach-Object {
    $p = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
    Write-Host ("  " + $_.LocalAddress + ":" + $_.LocalPort + "  PID=" + $_.OwningProcess + " " + $p.ProcessName)
  }
} else {
  Write-Host "  nothing listening - Apple service did not bind" -ForegroundColor Yellow
}

Write-Host "=== 5. bridge $LISTEN_PORT -> 127.0.0.1:$APPLE_PORT ===" -ForegroundColor Cyan
netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=$LISTEN_PORT 2>&1 | Out-Null
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=$LISTEN_PORT connectaddress=127.0.0.1 connectport=$APPLE_PORT | Out-Null
netsh interface portproxy show v4tov4 2>&1 | Select-String "$LISTEN_PORT" | ForEach-Object { Write-Host ("  " + $_.ToString().Trim()) }

Write-Host "=== 6. firewall ===" -ForegroundColor Cyan
$ruleName = "iOS relay $LISTEN_PORT"
if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort $LISTEN_PORT -Action Allow -Profile Any | Out-Null
  Write-Host "  rule added"
} else {
  Write-Host "  rule exists"
}

Write-Host ""
Write-Host "Done. Next: relay-handoff.ps1" -ForegroundColor Green
Write-Host "Then in WSL:"
Write-Host "  export USBMUXD_SOCKET_ADDRESS=`$(ip route show default | awk '{print `$3}'):$LISTEN_PORT"
Write-Host "  idevice_id -l"
