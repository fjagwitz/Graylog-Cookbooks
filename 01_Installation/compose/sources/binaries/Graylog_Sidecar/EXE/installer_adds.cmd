@echo off
SET WORKDIR=%~dp0
SET SERVERURL=""
SET APITOKEN=""
SET TAGS=["evaluation","adds","windows","applocker","powershell","defender","rds","forwarded","sysmon","ssh","bpa","bits"]
FOR /F "delims=" %%V IN ('dir /b %WORKDIR%*graylog*.exe') DO SET "INSTALLER=%%V"
FOR /F "delims=" %%V IN ('dir /b %WORKDIR%*filebeat*.exe') DO SET "FILEBEAT=%%V"

echo "[INFO] - INSTALL GRAYLOG SIDECAR "
echo "[WARN] - CONFIGURE TLS CONNECTION WITHOUT CERTIFICATE VALIDATION "
"%WORKDIR%%INSTALLER%" /S -SERVERURL=%SERVERURL% -APITOKEN=%APITOKEN% -TAGS=%TAGS% -TLS_SKIP_VERIFY=true

::
:: copy filebeat standalone into the sidecar folder
copy "%WORKDIR%%FILEBEAT%" "%PROGRAMFILES%\Graylog\sidecar\%FILEBEAT%"

exit 0