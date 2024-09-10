## WINDOWS MONITORING
### DNS Monitoring and Detection

### Preparation
- Read this Microsoft [Blog](https://techcommunity.microsoft.com/t5/core-infrastructure-and-security/secrets-from-the-deep-the-dns-analytical-log-part-1/ba-p/1875094)
- Activate DNS Logging on your Windows DNS Server: `wevtutil sl Microsoft-Windows-DNSServer/Analytical /Enabled:true /quiet`

### Log Collection
- Install [Graylog Sidecar](https://go2docs.graylog.org/current/getting_in_log_data/install_sidecar_on_windows.htm)
- (Optional) Install [NXLog](https://go2docs.graylog.org/current/getting_in_log_data/set_up_sidecar_collectors.htm#InstallCollectorsManually)