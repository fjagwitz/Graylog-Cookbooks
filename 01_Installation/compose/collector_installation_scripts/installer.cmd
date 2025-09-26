@echo off

msiexec.exe /q ALLUSERS=2 /m MSIJXGIB /i "nxlog-ce-3.2.2329.msi" INSTALLDIR="C:\Program Files\Graylog\sidecar\nxlog"

net stop nxlog 

"C:\Program Files\Graylog\nxlog\nxlog" -u

exit