$sidecarYml = 'C:\Program Files\Graylog\sidecar\sidecar.yml'

$collectorAcl = @"

collector_binaries_accesslist:
  - "C:\\Program Files\\Graylog\\sidecar\\filebeat.exe"
  - "C:\\Program Files\\Graylog\\sidecar\\winlogbeat.exe"  
  - "C:\\Program Files\\Graylog\\sidecar\\heartbeat.exe"
  - "C:\\Program Files\\Graylog\\Sidecar\\nxlog\\nxlog.exe"
"@

$collectorAcl | Out-File $sidecarYml -Append -Encoding utf8

Set-TimeZone -Id UTC

Restart-Service graylog-sidecar 

Exit 
