# ============================================================================
#  relay-handoff.ps1
#  ---------------------------------------------------------------------------
#  Give the iPhone back to Windows so Apple's service can enumerate it.
#
#  `usbipd detach` alone is NOT enough: the device stays in usbipd's shared set
#  and AppleMobileDeviceService never sees it. You then get a relay TCP port
#  that accepts connections but `idevice_id -l` prints nothing.
#
#  `usbipd unbind` releases it fully; Windows re-binds its normal driver stack.
#
#  ASCII-only (PowerShell 5.1 reads .ps1 as ANSI).
#
#  Usage:
#    powershell -File relay-handoff.ps1 [-BusId 2-2] [-Wait 150]
# ============================================================================
param(
  [string]$BusId = "",
  [int]$Wait = 150,
  [int]$Port = 27016
)

$ErrorActionPreference = 'Continue'
$usbipd = "C:\Program Files\usbipd-win\usbipd.exe"

Write-Host "=== 1. find the iPhone ===" -ForegroundColor Cyan
$line = (& $usbipd list 2>&1 | Select-String "05ac")
if (-not $line) { Write-Host "  no Apple device connected" -ForegroundColor Red; exit 1 }
Write-Host ("  " + $line.ToString().Trim())
if (-not $BusId) {
  $BusId = ($line.ToString() -split '\s+')[0]
}
Write-Host ("  busid = " + $BusId)

Write-Host "=== 2. detach ===" -ForegroundColor Cyan
if ($line -match 'Attached') {
  & $usbipd detach --busid $BusId 2>&1 | Out-Null
  Write-Host "  detached"
  Start-Sleep -Seconds 3
}

Write-Host "=== 3. unbind (full handoff to Windows) ===" -ForegroundColor Cyan
& $usbipd unbind --busid $BusId 2>&1 | ForEach-Object { Write-Host ("  " + $_) }
Start-Sleep -Seconds 4
(& $usbipd list 2>&1 | Select-String "05ac") | ForEach-Object { Write-Host ("  now: " + $_.ToString().Trim()) }

Write-Host "=== 4. restart Apple service ===" -ForegroundColor Cyan
$svc = Get-Service | Where-Object { $_.DisplayName -like '*Apple Mobile*' } | Select-Object -First 1
if ($svc) {
  sc.exe stop "$($svc.Name)" | Out-Null
  Start-Sleep -Seconds 3
  sc.exe start "$($svc.Name)" | Out-Null
  for ($i = 0; $i -lt 15; $i++) { Start-Sleep -Seconds 1; if ((Get-Service $svc.Name).Status -eq 'Running') { break } }
  Write-Host ("  " + (Get-Service $svc.Name).Status)
} else {
  Write-Host "  Apple service missing - run: winget install --id Apple.AppleMobileDeviceSupport" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== 5. UNLOCK THE IPHONE AND TAP 'TRUST' ===" -ForegroundColor Yellow
Write-Host "    (iOS asks again because this is a 'new computer' from its view)"
Write-Host ("    polling for $Wait s ...")

$found = $false
for ($i = 1; $i -le [math]::Ceiling($Wait / 5); $i++) {
  $out = wsl -e bash -lc "H=`$(ip route show default | awk '{print `$3}' | head -1); USBMUXD_SOCKET_ADDRESS=`$H:$Port idevice_id -l 2>/dev/null" 2>&1 | Out-String
  $udid = ($out | Select-String -Pattern '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}')
  if ($udid) {
    Write-Host ("  [" + $i + "] DEVICE: " + $udid.Matches[0].Value) -ForegroundColor Green
    $found = $true
    break
  }
  Write-Host ("  [" + $i + "] waiting for trust...")
  Start-Sleep -Seconds 5
}

if (-not $found) {
  Write-Host "  device never appeared." -ForegroundColor Yellow
  Write-Host "  - is the phone unlocked? a locked phone cannot show the trust dialog"
  Write-Host "  - try unplugging and replugging the USB cable"
  Write-Host "  - verify 27016 bridge: netsh interface portproxy show v4tov4"
}

Write-Host ""
Write-Host "Next (in WSL): bash install-app.sh <file.ipa>" -ForegroundColor Green
