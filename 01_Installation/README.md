## Prepare Server System

Create a virtual machine:

- CPU Cores: at least 8
- Memory: at least 32 GB
- Storage: at least 600 GB in **/opt** (depending on the amount of data you plan to Ingest over a defined timeframe)
- Operating System: Ubuntu LTS, Standard Setup without additional packages
- Configured IP-Address, DNS resolution and Access to the Internet
- Have an SSL certificate handy for the Web UI

_Heads-up_: If you are using the Proxmox Hypervisor, make sure you configure the CPU type [with AVX support](https://www.techtutorials.tv/sections/promox/proxmox-custom-cpus), otherwise you will observe MongoDB Containers being caught in a restart loop (see https://github.com/docker-library/mongo/issues/619). 

_Heads-up_: Make sure to work with **Memory Reservation** for your VM as you MUST avoid the hypervisor to use Graylog's Memory for other services. 

Depending on your setup, you might want to add hypervisor-specific guest tools and additional software required by organizational policy.

## Install Graylog

**Before** you start, make a **Snapshot** of your Ubuntu machine; the Installation Script contains practically **no error handling**; in case it breaks at some point you can **revert** the machine to the initial state and restart the Installation Script.

Get it from here:

    curl -sO https://raw.githubusercontent.com/fjagwitz/Graylog-Cookbooks/refs/heads/Graylog-7.0/01_Installation/install-graylog.sh && chmod +x install-graylog.sh && sudo ./install-graylog.sh

The system is accessible via

- http(s)://ipaddress
- http(s)://hostname
- http(s)://fqdn

## Get a license

- Graylog Open: This system can be tested without a license but limited functionality (Graylog Open Features). Be aware of the legal constraints when it comes to processing PII data such as authentication logs and others, as Graylog Open does not provide an Audit Trail for administrator activities. 
- Graylog Enterprise and Graylog Security: You need a trial license (xGB/day, up to 14 days). Please get in touch with your local [Graylog Partner](https://cybercompare.com/de/providers/graylog-germany-gmbh/#provider-contact) to align on the Evaluation Process and keep your Cluster-ID (displayed after Installation has finished) at hand.  

## Folder Structure

The installation script will create a few folders and populate these with helpful content to understand the Graylog capabilities:

    /opt
        |
        |--/graylog
                |
                |--docker-compose.yaml
                |--graylog.env
                |--opensearch.env
                |--your_graylog_credentials.txt
                |
                |--/archives
                |
                |--/assetdata
                |
                |--/configuration
                |
                |--/contentpacks
                |
                |--/database
                |       |
                |       |--/datanode1
                |       |
                |       |--/datanode2
                |       |
                |       |--/datanode3
                |       |
                |       |--/warm_tier
                |
                |--/datalake
                |
                |--/input_tls
                |
                |--/journal1
                |
                |--/journal2
                |
                |--/logsamples
                |
                |--/lookuptables
                |
                |--/maxmind
                |
                |--/nginx1
                |     |
                |     |--http.conf
                |     |--nginx.conf
                |     |--stream.conf
                |     |
                |     |--ssl
                |         |--cert.crt
                |         |--cert.key
                |
                |--/nginx2
                |     |
                |     |--http.conf
                |     |--nginx.conf
                |
                |--/notifications
                |
                |--/prometheus
                |
                |--/rootcerts
                |
                |--/samba
                |
                |--/sources
    

**/opt/graylog**:

- **/archives** _(must be owned by the user:group with the id 1100)_: this folder is used when the "ARCHIVE" feature (Enterprise) is tested. You can mount any remote storage to that folder.
- **/assetdata**: this folder is intended to store any type of Asset Collection you might have (e.g. Excel or CSV files). The Folder is accessible for Windows machines via Samba Share (credentials are the same as for the WebUI).
- **/configuration**: this folder contains Graylog's configuration in a MongoDB database.
- [**/contentpacks**](https://github.com/fjagwitz/Graylog-Cookbooks/tree/main/01_Installation/compose/contentpacks): this folder contains Graylog Content Packs to pre-populate your Graylog Installation with a few Configurations in order to accelerate the process.
- **/database** _(must be owned by the user:group with the id 1000)_: this folder contains Graylog's log data in an Opensearch database.
- **/datalake** _(must be owned by the user:group with the id 1100)_: this folder contains data that is prepared for requirement-driven ingestion (Data Routing). You can mount any remote storage to that folder.
- **/journal[12]** _(must be owned by the user:group with the id 1100)_: this folder is used for the Graylog Journal. It must provide at least 10GB of Storage. You can mount any remote storage to that folder.
- [**/lookuptables**](https://github.com/fjagwitz/Graylog-Cookbooks/tree/main/01_Installation/compose/lookuptables): this folder contains a few lookuptables that can be used by Graylog Data Adapters. The Folder is accessible for Windows machines via Samba Share (credentials are the same as for the WebUI).
- **/maxmind**: this folder contains the GeoIP databases to be used by the Graylog Geo-Location Processor.
- [**/nginx1**](https://github.com/fjagwitz/Graylog-Cookbooks/tree/main/01_Installation/compose/nginx1): this folder contains the nginx configuration files for the nginx container.
- **/nginx1/ssl**: this folder contains the nginx certificates for https connections.
- [**/nginx2**](https://github.com/fjagwitz/Graylog-Cookbooks/tree/main/01_Installation/compose/nginx2): this folder contains the nginx configuration files for the internal nginx container within the Graylog Stack. It stores and provides lookup tables used with Graylog's _"DSV File from HTTP"_ adapter.
- **/notifications** _(must be owned by the user:group with the id 1100)_: this folder contains scripts being used when the "SCRIPT NOTIFICATION" feature (Enterprise) is tested.
- [**/prometheus**](https://github.com/fjagwitz/Graylog-Cookbooks/tree/main/01_Installation/compose/prometheus): this folder contains configuration data to get metrics from Graylog to Grafana.
- [**/sources**](https://github.com/fjagwitz/Graylog-Cookbooks/tree/main/01_Installation/compose/sources): this folder contains sources that help you getting started with Graylog
