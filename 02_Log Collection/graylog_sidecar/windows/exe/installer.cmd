@echo off
SET workdir=%~dp0
SET installer=graylog_sidecar_installer_1.5.1-1.exe
REM 
REM Please adapt the following variables to your needs
REM 
SET serverurl=https://my.graylog.local/api
SET apitoken=fmgqa6rckfm6b4c1kvgfo54371uv7atsu2esuvt9es7jhlgogbv
SET tags=["default","adds"]
SET tlsskipverify=true
SET updateinterval=60s

"%workdir%%installer%" /S -SERVERURL=%serverurl% -APITOKEN=%apitoken% -TAGS=%tags% -TLSSKIPVERIFY=%tlsskipverify% -UPDATEINTERVAL=%updateinterval%

REM Please do not uncomment the following line unless you fully understand what the command does: 
REM - adding an additional binary that will be controlled by Graylog Sidecar
REM - setting the system time to UTC (!!!)
REM - restarting the sidecar service
REM 
REM powershell.exe -ExecutionPolicy Bypass -File  .\configure-sidecar.ps1
REM 

exit