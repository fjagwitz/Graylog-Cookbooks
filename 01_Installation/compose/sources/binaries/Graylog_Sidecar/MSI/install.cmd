@echo off

SET WORKDIR=%~dp0
SET SIDECAR_YML=%PROGRAMFILES%\Graylog\sidecar\sidecar.yml
FOR /F "delims=" %%V IN ('dir /b %WORKDIR%*filebeat*.exe') DO SET "FILEBEAT=%%V"
FOR /F "delims=" %%V IN ('dir /b %WORKDIR%*graylog*.msi') DO SET "INSTALLER=%%V"

echo "[INFO] - INSTALL GRAYLOG SIDECAR "
echo "[WARN] - CONFIGURE TLS CONNECTION WITHOUT CERTIFICATE VALIDATION "
msiexec.exe /q /i "%WORKDIR%%INSTALLER%" 

::
:: copy sidecar configuration file into the sidecar folder
:: copy filebeat standalone into the sidecar folder
copy "%WORKDIR%sidecar.yml" "%SIDECAR_YML%"
copy "%WORKDIR%%FILEBEAT%" "%PROGRAMFILES%\Graylog\sidecar\%FILEBEAT%"

::
:: enable dns etw-logging on system level
:: wevtutil sl Microsoft-Windows-DNSServer/Analytical /Enabled:true /quiet

::
:: enable and start graylog-sidecar as a system service

"%PROGRAMFILES%\Graylog\sidecar\graylog-sidecar.exe" -service install
"%PROGRAMFILES%\Graylog\sidecar\graylog-sidecar.exe" -service start

exit 0