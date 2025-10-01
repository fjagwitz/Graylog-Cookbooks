# Graylog-Cookbooks
## Sidecar Installation

Graylog Sidecar can be installed on [Windows](https://go2docs.graylog.org/current/getting_in_log_data/install_sidecar_on_windows.htm#InstalltheSidecarServiceinWindows) via EXE or MSI Installer. 

The EXE Installer allows you to configure Sidecar without giving you access to all options that you can set via [sidecar.yml](https://go2docs.graylog.org/current/getting_in_log_data/install_sidecar_on_windows.htm#sidecarymlConfigurationReference). In some cases it might be helpful to refine the configuration file after installation; this example shows you that could look like via Powershell. 

The MSI Installer allows you to install Sidecar without any additional configuration but comes with the typical advantages of an MSI package that can be used when Configuration Management tools are in use. However, after installing Sidecar via MSI package, you ALWAYS need to create the sidecar.yml file on your own based on an example file in the Sidecar base folder (C:\Program Files\Graylog\Sidecar). You then need to enable and start the service as described in the [documentation](https://go2docs.graylog.org/current/getting_in_log_data/install_sidecar_on_windows.htm#InstalltheSidecarServiceinWindows). 

In this repo you will find examples of an install script as well as for configuration scripts. Please avoid using them as-is but consider them as template for your own version of installation package. 