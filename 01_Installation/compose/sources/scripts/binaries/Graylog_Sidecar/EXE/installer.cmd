@echo off
SET workdir=pushd %~dp0

echo "Das ist jetzt unser Arbeitsverzeichnis: %workdir%"

SET installer=graylog_sidecar_installer_1.5.0-1.exe
SET serverurl=https://gls.fritzdata.de/api
SET apitoken=fmgqa6rckfm6b4c1kvgfo54371uv7utsu2esuvt9es7jllgogbv
SET tags=["VLAN148","Windows"]

REM "%workdir%%installer%" /S -SERVERURL=%serverurl% -APITOKEN=%apitoken% -TAGS=%tags%

REM powershell.exe -ExecutionPolicy Bypass -File  .\configure-sidecar.ps1

pause