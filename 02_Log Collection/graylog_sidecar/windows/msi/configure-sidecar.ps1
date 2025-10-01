##############################################################################
#
# Make sure to change all of the values below to make them appropriate for your environment
#
##############################################################################

# The URL to the Graylog server API.
# Default: "http://127.0.0.1:9000/api/"
$serverURL = "https://my.graylog.intern/api"

# The API token to use to authenticate against the Graylog server API.
# How to create an API token (https://go2docs.graylog.org/current/getting_in_log_data/install_sidecar_on_windows.htm#create-an-api-token)
$serverApiToken = "jpmalvsh9n1pcbrjttkpp393tidkhglhgrkify40esg5ajim00v"

# The update interval in secods. This configures how often the sidecar will
# contact the Graylog server for keep-alive and configuration update requests.
# Default: 10
$updateInterval = "30"

# This configures if the sidecar should skip the verification of TLS connections.
# Default: false
$tlsSkipVerify = "false"

# This enables/disables the transmission of detailed sidecar information like
# collector statues, metrics and log file lists. It can be disabled to reduce
# load on the Graylog server if needed. (disables some features in the server UI)
# Default: true
$sendStatus = "true"

# Add tags to your sidecar.yml that allow the Graylog Cluster to identify what type of server this is and what collector configurations apply best to this system
# Defining tags is something you can do along your requirements, no constraints (e.g. by server role or installed applications)
# This example assumes that the sidecar will be installed on a domain controller with the adds role installed

$tags = @"
tags:
  - windows
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

##############################################################################
#
# Make sure you changed all of the values above to make them appropriate for your environment
#
##############################################################################

##############################################################################
#
# Do not touch the following lines
#
##############################################################################

$sidecarExampleYmlFile = "$env:ProgramFiles\Graylog\sidecar\sidecar-example.yml"
$sidecarYmlFile= "$env:ProgramFiles\Graylog\sidecar\sidecar.yml"

$sidecarYml = Get-Content $sidecarExampleYmlFile

$sidecarYml=$sidecarYml -Replace "(server_url:\s\S*)", "server_url: `"$serverURL`""
$sidecarYml=$sidecarYml -Replace "(server_api_token:\s\S*)", "server_api_token: `"$serverApiToken`""
$sidecarYml=$sidecarYml -Replace "(update_interval:\s\S*)", "update_interval: $updateInterval"
$sidecarYml=$sidecarYml -Replace "(tls_skip_verify:\s\S*)", "tls_skip_verify: $tlsSkipVerify"
$sidecarYml=$sidecarYml -Replace "(send_status:\s\S*)", "send_status: $sendStatus"
$sidecarYml=$sidecarYml -Replace 'tags:\s\S*', $tags

$sidecarYml=$sidecarYml + $collectorAcl

Set-Content $sidecarYml -LiteralPath $sidecarYmlFile -Encoding ASCII -Force

##############################################################################
#
# Having all Systems on UTC is a good practice in the logging world: 
# https://www.tinybird.co/blog-posts/database-timestamps-timezones
# Consider uncommenting the line below that sets system time to UTC
#
##############################################################################

# Set-TimeZone -Id UTC

Exit 
