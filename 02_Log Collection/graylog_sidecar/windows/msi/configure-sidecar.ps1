$sidecarYml = Get-Content .\sidecar-example.yml
# Make sure to have the correct URL of the Graylog API. In case you have no reverse proxy in front of your Graylog Cluster, the Server URL should contain Port 9000, such as https://my.graylog.intern:9000/api
$serverURL = "https://my.graylog.intern/api"

# Make sure to create an API token (https://go2docs.graylog.org/current/getting_in_log_data/install_sidecar_on_windows.htm#create-an-api-token) for your Sidecar in the Graylog Web UI; such Sidecar tokens can be used for multiple Sidecars
$serverApiToken = "abc"

# Configure the Update Interval (how often will Graylog Sidecar check for an updated Collector Configuration); default is 10 seconds, this example uses 60 seconds
$updateInterval = "60"

# Configure whether or not the Sidecar will skip the TLS certificate. Should be "false", except in a few cases where you know what you do
$tlsSkipVerify = "false"

# Configure whether or not the Sidecar will send a status to your Graylog Cluster
$sendStatus = "true"

# Add tags to your sidecar.yml that allow the Graylog Cluster to identify what type of server this is and what collector configurations apply best to this system
$tags = @"
tags:
  - default
  - adds
"@

# Graylog Sidecar is allowed to create instances of all executables in the list. This is a Security Feature to avoid Sidecar starting all types of binaries in all paths (as it runs in "Local System" context). Adapt to your needs.
$collectorAcl = @"

collector_binaries_accesslist:
  - "C:\\Program Files\\Graylog\\sidecar\\filebeat.exe"
  - "C:\\Program Files\\Graylog\\sidecar\\winlogbeat.exe"
  - "C:\\Program Files\\Graylog\\sidecar\\heartbeat.exe"
  - "C:\\Program Files\\Graylog\\sidecar\\auditbeat.exe"
  - "C:\\Program Files\\Graylog\\sidecar\\metricbeat.exe"
  - "C:\\Program Files\\Graylog\\sidecar\\packetbeat.exe"
  - "C:\\Program Files\\Graylog\\sidecar\\nxlog\\nxlog.exe"
  - "C:\\Program Files\\Filebeat\\filebeat.exe"
  - "C:\\Program Files\\Packetbeat\\packetbeat.exe"
  - "C:\\Program Files\\Metricbeat\\metricbeat.exe"
  - "C:\\Program Files\\Heartbeat\\heartbeat.exe"
  - "C:\\Program Files\\Auditbeat\\auditbeat.exe"
  - "C:\\Program Files\\nxlog\\nxlog.exe"
"@

$sidecarYml=$sidecarYml.Replace('server_url: "http://127.0.0.1:9000/api/"', "server_url: `"$serverURL`"")
$sidecarYml=$sidecarYml.Replace('server_api_token: ""', "server_api_token: `"$serverApiToken`"")
$sidecarYml=$sidecarYml.Replace('update_interval: 10', "update_interval: $updateInterval")
$sidecarYml=$sidecarYml.Replace('tls_skip_verify: false', "tls_skip_verify: $tlsSkipVerify")
$sidecarYml=$sidecarYml.Replace('send_status: true', "send_status: $sendStatus")
$sidecarYml=$sidecarYml.Replace("tags: []", "$tags")

$sidecarYml=$sidecarYml + $collectorAcl

Set-Content $sidecarYml -LiteralPath .\sidecar.yml -Encoding UTF8 -Force

# Having all Systems on UTC is a good practice in the logging world. Uncomment based on your requirements. 
# Set-TimeZone -Id UTC

Exit 
