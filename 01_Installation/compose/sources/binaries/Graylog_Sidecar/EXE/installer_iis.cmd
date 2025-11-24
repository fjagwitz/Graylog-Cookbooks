@echo off
SET workdir=%~dp0
SET serverurl=""
SET apitoken=""
SET tags=["Evaluation","Windows","IIS"]
FOR /F "delims=" %%V IN ('dir /b *.exe') DO SET "installer=%%V"
echo %installer%

"%workdir%%installer%" /S -SERVERURL=%serverurl% -APITOKEN=%apitoken% -TAGS=%tags%

exit