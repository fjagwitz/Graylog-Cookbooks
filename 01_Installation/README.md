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

    wget -q https://raw.githubusercontent.com/fjagwitz/Graylog-Cookbooks/main/01_Installation/install-graylog6.sh && chmod +x install-graylog6.sh && sudo ./install-graylog6.sh

The system is accessible via

- http(s)://ipaddress
- http(s)://hostname
- http(s)://fqdn

## Get a license

Once set up, the system can be tested without a license but limited functionality. For evaluating Graylog Enterprise & Security Features, you need a trial license. Send the Cluster-ID (displayed when the script finishes) to your local Graylog Solution Engineer and get it within a few days.

## Folder Structure

The installation script will create a few folders and populate these with helpful content to understand the Graylog capabilities:

    /opt
        |
        |--/graylog
        |       |
        |       |--/archives
        |       |
        |       |--/contentpacks
        |       |
        |       |--/journal
        |       |
        |       |--/lookuptables
        |       |
        |       |--/maxmind
        |       |
        |       |--/nginx
        |       |     |
        |       |     |--http.conf
        |       |     |--nginx.conf
        |       |     |--stream.conf
        |       |     |
        |       |     |--ssl
        |       |         |--cert.crt
        |       |         |--cert.key
        |       |
        |       |--/notifications
        |       |
        |       |--/prometheus
        |
        |
        |--/opensearch
                |
                |--datanode1
                |
                |--datanode2
                |
                |--datanode3

/opt/graylog:

- **/archives** _(must be owned by the user:group with the id 1100)_: this folder is used when the "ARCHIVE" feature (Enterprise) is tested. You can mount any remote storage to that folder.
- **/contentpacks**: this folder contains Graylog Content Packs to pre-populate your Graylog Installation with a few Configurations in order to accelerate the process.
- **/journal** _(must be owned by the user:group with the id 1100)_: this folder is used for the Graylog Journal. It must provide at least 5GB of Storage. You can mount any remote storage to that folder.
- **/lookuptables**: this folder contains a few lookuptables that can be used by Graylog Data Adapters. The Folder is accessible for Windows machines via Samba Share (credentials are the same as for the WebUI).
- **/maxmind**: this folder contains the GeoIP databases to be used by the Graylog Geo-Location Processor.
- **/nginx**: this folder contains the nginx configuration files for the nginx container.
- **/nginx/ssl**: this folder contains the nginx certificates for https connections.
- **/notifications** _(must be owned by the user:group with the id 1100)_: this folder contains scripts being used when the "SCRIPT NOTIFICATION" feature (Enterprise) is tested.
- **/prometheus**: this folder contains configuration data to get metrics from Graylog to Grafana.

/opt/opensearch _(must be owned by the user:group with the id 1000)_:

- **datanode[1-3]**: these folders contain the Opensearch Data. You can mount any remote storage to that folder.

## Configure Nginx

Nginx certificates are stored in the Ubuntu machine under ```/opt/graylog/nginx/ssl``` and can be replaced:

the easy way:

- store your certificates under /opt/graylog/nginx/ssl
- rename your own certificate to cert.crt and cert.key

the flexible way:

- store your certificates under /opt/graylog/nginx/ssl
- change the corresponding settings in /opt/graylog/nginx/http.conf
