@echo off

SET WORKDIR=%~dp0
SET SIDECAR_FOLDER=%PROGRAMFILES%\Graylog\sidecar
SET SIDECAR_YML=sidecar.yml

FOR /F "delims=" %%V IN ('dir /b %WORKDIR%*filebeat*.exe') DO SET "FILEBEAT=%%V"
FOR /F "delims=" %%V IN ('dir /b %WORKDIR%*winlogbeat*.exe') DO SET "WINLOGBEAT=%%V"
FOR /F "delims=" %%V IN ('dir /b %WORKDIR%*graylog*.msi') DO SET "INSTALLER=%%V"

echo [INFO] - INSTALL GRAYLOG SIDECAR
msiexec.exe /q /i "%WORKDIR%%INSTALLER%" 

::
:: copy sidecar configuration file into the sidecar folder
echo [INFO] - CONNECT SIDECAR WITH YOUR GRAYLOG CLUSTER
robocopy %WORKDIR% "%SIDECAR_FOLDER%" %SIDECAR_YML% /NFL /NDL /NJH /NJS >nul

::
:: copy filebeat standalone into the sidecar folder
:: copy winlogbeat standalone into the sidecar folder

echo [INFO] - REPLACE BEATS OSS BY BEATS STANDALONE
robocopy %WORKDIR% "%SIDECAR_FOLDER%" %FILEBEAT% /NFL /NDL /NJH /NJS >nul
robocopy %WORKDIR% "%SIDECAR_FOLDER%" %WINLOGBEAT% /NFL /NDL /NJH /NJS >nul

::
:: check for DNS Server role installed on the system
:: enable dns etw-logging on system level
SET DNS="powershell (Get-WindowsFeature -Name DNS).InstallState"
FOR /F "tokens=*" %%V IN (' %DNS% ') DO SET DNSSERVER=%%V

:: enable dns etw-logging on system level
:: wevtutil sl Microsoft-Windows-DNSServer/Analytical /Enabled:true /quiet
IF %DNSSERVER%==Installed (
echo.
echo.
echo 	To activate DNS Logging on this System, follow the instructions on 
echo 	https://learn.microsoft.com/en-us/windows-server/networking/dns/dns-logging-and-diagnostics
echo.
echo 	In case you are more the TL;DR type of Admin, just type the command below into your console:  
echo.
echo 	wevtutil sl Microsoft-Windows-DNSServer/Analytical /Enabled:true /quiet
echo.
echo.  
)

::
:: enable and start graylog-sidecar as a system service

"%PROGRAMFILES%\Graylog\sidecar\graylog-sidecar.exe" -service install
"%PROGRAMFILES%\Graylog\sidecar\graylog-sidecar.exe" -service start

SET SIDECAR="sc query graylog-sidecar | FIND /C "RUNNING""
FOR /F "tokens=*" %%V IN (' %SIDECAR% ') DO SET SIDECARCONNECTION=%%V
if %SIDECARCONNECTION%==1 echo [INFO] - SIDECAR SUCCESSFULLY CONNECTED TO YOUR GRAYLOG CLUSTER

echo [WARN] - CONFIGURED TLS CONNECTION WITHOUT CERTIFICATE VALIDATION 
echo [WARN] - CONFIGURED TLS IN A SECURE WAY NEEDS MANUAL INTERACTION 
echo [WARN] - REVIEW SIDECAR.YML FILE IN THE SIDECAR FOLDER (%SIDECAR_FOLDER%) IF DESIRED
echo [WARN] - WILL NOW BE OPENED FOR YOUR CONVENIENCE AFTER QUITTING

::
:: open sidecar.yml in Windows Notepad
start notepad %SIDECAR_FOLDER%\%SIDECAR_YML% 

echo [INFO] - TO QUIT PRESS ENTER

pause >nul


exit