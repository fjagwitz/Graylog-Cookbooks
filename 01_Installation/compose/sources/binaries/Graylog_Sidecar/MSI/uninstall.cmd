@echo off

SET WORKDIR=%~dp0
SET SIDECAR_YML=%PROGRAMFILES%\Graylog\sidecar\sidecar.yml
FOR /F "delims=" %%V IN ('dir /b %WORKDIR%*graylog*.msi') DO SET "INSTALLER=%%V"

echo "[INFO] - UNINSTALL GRAYLOG SIDECAR "
::
:: stop and disable graylog-sidecar as a system service
"%PROGRAMFILES%\Graylog\sidecar\graylog-sidecar.exe" -service stop
"%PROGRAMFILES%\Graylog\sidecar\graylog-sidecar.exe" -service uninstall

msiexec.exe /q /x "%WORKDIR%%INSTALLER%" 

::
:: remove graylog folder
rmdir /S /Q "%PROGRAMFILES%\Graylog"

exit 0