@echo off
SET workdir=%~dp0
SET installer=graylog_sidecar_installer_1.5.1-1.msi

msiexec /i "%workdir%%installer%" /qn /passive /norestart

powershell.exe -ExecutionPolicy Bypass -File  .\configure-sidecar.ps1

"C:\Program Files\graylog\sidecar\graylog-sidecar.exe" -service install
"C:\Program Files\graylog\sidecar\graylog-sidecar.exe" -service start

exit