# Windows - Detect Privileged and Service Accounts

## Requirements

- Graylog Operations, Security
- Appropriate Windows Audit Policy Settings

## Prepwork

- ensure Graylog is on the latest version
- ensure Windows is properly configured and creates the logs you need to detect Shutdown/Reboot events
- ensure your Sidecar is properly configured to control the collector on your Windows machine (Winlogbeat, NXLog CE or NXLog Enterprise)
- configure a Collectors Configuration to collect the events for Shutdown/Reboot and send them to your Graylog instance

## Execution
