NXLog Community Edition can be downloaded at https://nxlog.co/downloads/nxlog-ce#nxlog-community-edition

Please follow the Graylog Installation Instructions at https://go2docs.graylog.org/current/getting_in_log_data/set_up_sidecar_collectors.htm#nxlog-on-windows 

Instead you can use the "installer.cmd" and place it within the same folder as the "nxlog-ce-3.2.2329.msi" binary. It will install NXLog within the Graylog Sidecar Directory and remove the native NXLog Service in favour of letting Graylog Sidecar control the NXLog Collector. 