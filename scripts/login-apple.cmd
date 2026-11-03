@echo off
REM ============================================================================
REM  login-apple.cmd
REM  ---------------------------------------------------------------------------
REM  Open an interactive console for xtool auth login.
REM
REM  ## Why a console window, not a script
REM
REM  Signing needs an Apple ID login. It prompts for account + password, and the
REM  agent must not handle those. Three hard-won details:
REM
REM  1. DO NOT pipe the command (| tee). Without a real TTY the password prompt
REM     (raw mode, echo disabled) receives no input. The symptom is deceptive:
REM     "Apple ID types fine, the password field takes nothing".
REM     `script` allocates a pty AND keeps a log - use it.
REM
REM  2. Error -22406 "Enter the correct password" means either a typo (the field
REM     is invisible) or that the account needs an APP-SPECIFIC PASSWORD:
REM       https://appleid.apple.com -> Sign-In and Security
REM       -> App-Specific Passwords -> generate
REM     Paste it whole, hyphens included.
REM
REM  3. --mode password skips the interactive "0: API Key / 1: Password" menu.
REM     Leaving that menu unanswered is why an earlier attempt just sat there.
REM
REM  A free Apple ID works; its certificate expires after 7 days (paid: 90).
REM ============================================================================
title iOS - Apple ID Login
cls
echo ============================================================
echo    xtool Apple ID Login    (mode: password, real TTY)
echo ============================================================
echo.
echo   You will be asked for:
echo     1) Apple ID   (email)
echo     2) Password   (typing is INVISIBLE - that is normal)
echo     3) 6-digit 2FA code, if 2FA is enabled
echo.
echo   If you see -22406 (wrong password):
echo     - retype slowly (the field shows nothing)
echo     - or paste an App-Specific Password from appleid.apple.com
echo.
echo ============================================================
echo.

REM script gives the child a pty so the password prompt works,
REM while still recording everything into /root/login.log
wsl.exe -e bash -lc "export PATH=/opt/swift641/usr/bin:$PATH; cd ~; rm -f /root/login.log; script -q -e -c 'xtool auth login --mode password' /root/login.log; echo; echo '--- auth status ---'; xtool auth status"

echo.
echo ============================================================
echo   Log: /root/login.log
echo   Success looks like:  Logged in.   - Team ID: XXXXXXXXXX
echo ============================================================
pause
