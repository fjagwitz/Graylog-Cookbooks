## WINDOWS MONITORING
### DNS Monitoring and Detection

### Preparation
- Read https://techcommunity.microsoft.com/t5/core-infrastructure-and-security/secrets-from-the-deep-the-dns-analytical-log-part-1/ba-p/1875094
- Activate DNS Logging on your Windows DNS Server: `wevtutil sl Microsoft-Windows-DNSServer/Analytical /Enabled:true /quiet`