# Graylog Installation

## Prepare Server System

Create a virtual machine:

- CPU Cores: at least 8
- Memory: at least 32 GB
- Storage: at least 480 GB
- Operating System: Ubuntu LTS, Standard Setup without additional packages
- Configured IP-Address, DNS resolution and Access to the Internet

Depending on your setup, you might want to add hypervisor-specific guest tools and additional software required by organizational policy.

## Install Graylog

Before you start, make a Snapshot of your Ubuntu machine; the Installation Script contains practically no error handling; in case it breaks at some point you can revert the machine to the initial state and restart the Installation Script.

Get it from here:

    wget -q https://raw.githubusercontent.com/fjagwitz/Graylog-Cookbooks/main/01_Installation/install-graylog6-v1.sh && chmod +x install-graylog6-v1.sh && ./install-graylog6-v1.sh

Don't use this:

    wget -q https://raw.githubusercontent.com/fjagwitz/Graylog-Cookbooks/main/01_Installation/install-graylog6-v2.sh && chmod +x install-graylog6-v2.sh && ./install-graylog6-v2.sh

The system is accessible via

- http(s)://ipaddress
- http(s)://fqdn

## Get a license

For testing Graylog Enterprise & Security Features, you need a test license. Send the Cluster-ID (displayed when the script finishes) to your local Graylog Solution Engineer and get it within a few days.

## Folder Structure

## Configure Nginx

Nginx certificates are stored in the Ubuntu machine under ```/opt/graylog/nginx/ssl``` and can be replaced:

the easy way:

- store your certificates under /opt/graylog/nginx/ssl
- rename your own certificate to cert.crt and cert.key

the flexible way:

- store your certificates under /opt/graylog/nginx/ssl
- change the corresponding settings in /opt/graylog/nginx/http.conf
