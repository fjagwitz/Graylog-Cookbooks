@echo off

SET WORKDIR=%~dp0
SET SIDECAR_YML=%PROGRAMFILES%\Graylog\sidecar\sidecar.yml
FOR /F "delims=" %%V IN ('dir /b %WORKDIR%*graylog*.msi') DO SET "GRAYLOG=%%V"
FOR /F "delims=" %%V IN ('dir /b %WORKDIR%*nxlog*.msi') DO SET "NXLOG=%%V"

echo [INFO] - DISABLE GRAYLOG SIDECAR SERVICE
::
:: Stop and Disable Graylog-Sidecar as a system service
"%PROGRAMFILES%\Graylog\sidecar\graylog-sidecar.exe" -service stop > NUL 2>&1
"%PROGRAMFILES%\Graylog\sidecar\graylog-sidecar.exe" -service uninstall > NUL 2>&1

echo [INFO] - UNINSTALL GRAYLOG SIDECAR
::
:: Uninstall Graylog Sidecar
msiexec.exe /q /x "%WORKDIR%%GRAYLOG%" 

echo [INFO] - UNINSTALL NXLOG CE
::
:: Uninstall NXLog
msiexec.exe /x "%WORKDIR%%NXLOG%" /qb 

echo [INFO] - CLEANUP FOLDERS
::
:: remove NXLog Folder
rmdir /S /Q "%PROGRAMFILES%\nxlog" > NUL 2>&1

::
:: remove Graylog Folder
rmdir /S /Q "%PROGRAMFILES%\Graylog" > NUL 2>&1

echo [INFO] - SUCCESSFULLY DONE - TO QUIT PRESS ENTER

pause > NUL 2>&1

exit 0