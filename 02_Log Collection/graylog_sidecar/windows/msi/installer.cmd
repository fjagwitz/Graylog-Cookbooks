@echo off
SET workdir=%~dp0
SET installer=graylog-sidecar-1.5.1-1.msi

msiexec /i "%workdir%%installer%" /qn /quiet /norestart

powershell.exe -ExecutionPolicy Bypass -File  %workdir%configure-sidecar.ps1

"C:\Program Files\graylog\sidecar\graylog-sidecar.exe" -service install
"C:\Program Files\graylog\sidecar\graylog-sidecar.exe" -service start

exit