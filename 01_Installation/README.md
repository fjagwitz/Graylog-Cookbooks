## Prepare Server System

Create a virtual machine:

- CPU Cores: at least 8
- Memory: at least 32 GB
- Storage: at least 480 GB (depending on the amount of data you plan to Ingest over a defined timeframe)
- Operating System: Ubuntu LTS, Standard Setup without additional packages
- Configured IP-Address, DNS resolution and Access to the Internet

_Heads-up_: If you are using the Proxmox Hypervisor, make sure you configure the CPU type as "host", otherwise you will observe Opensearch Containers to be caught in a restart loop (see https://github.com/ansible/awx/issues/11879). 

Depending on your setup, you might want to add hypervisor-specific guest tools and additional software required by organizational policy.

## Install Graylog

Before you start, make a Snapshot of your Ubuntu machine; the Installation Script contains practically no error handling; in case it breaks at some point you can revert the machine to the initial state and restart the Installation Script.

Get it from here:

    curl -sO https://raw.githubusercontent.com/fjagwitz/Graylog-Cookbooks/refs/heads/Graylog-6.2/01_Installation/install-graylog.sh && chmod +x install-graylog.sh && sudo ./install-graylog.sh

The system is accessible via

- http(s)://ipaddress
- http(s)://hostname
- http(s)://fqdn

## Get a license

- Graylog Open: This system can be tested without a license but limited functionality (Graylog Open Features). 
- Graylog Small Business License (2GB/day, 1 year): For evaluating some of the Graylog Enterprise features, feel free to download a [Small Business License](https://graylog.org/products/small-business); enjoy the additional features
- Graylog Enterprise and Graylog Security: You need a trial license (xGB/day, up to 14 days). Please get in touch with your local [Graylog Partner](https://cybercompare.com/de/providers/graylog-germany-gmbh/#provider-contact) to align on the Evaluation Process and keep your Cluster-ID (displayed after Installation has finished) at hand.  

## Folder Structure

The installation script will create a few folders and populate these with helpful content to understand the Graylog capabilities:

    /opt
        |
        |--/graylog
        |       |
        |       |--docker-compose.yaml
        |       |--.env
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
        |       |--/nginx1
        |       |     |
        |       |     |--http.conf
        |       |     |--nginx.conf
        |       |     |--stream.conf
        |       |     |
        |       |     |--ssl
        |       |         |--cert.crt
        |       |         |--cert.key
        |       |
        |       |--/nginx2
        |       |     |
        |       |     |--http.conf
        |       |     |--nginx.conf
        |       |
        |       |--/notifications
        |       |
        |       |--/prometheus
        |       |
        |       |--/warehouse
        |
        |
        |--/opensearch
                |
                |--/datanode1
                |
                |--/datanode2
                |
                |--/datanode3
                |
                |--/searchable_snapshots

**/opt/graylog**:

- **/archives** _(must be owned by the user:group with the id 1100)_: this folder is used when the "ARCHIVE" feature (Enterprise) is tested. You can mount any remote storage to that folder.
- [**/contentpacks**](https://github.com/fjagwitz/Graylog-Cookbooks/tree/main/01_Installation/compose/contentpacks): this folder contains Graylog Content Packs to pre-populate your Graylog Installation with a few Configurations in order to accelerate the process.
- **/journal** _(must be owned by the user:group with the id 1100)_: this folder is used for the Graylog Journal. It must provide at least 5GB of Storage. You can mount any remote storage to that folder.
- [**/lookuptables**](https://github.com/fjagwitz/Graylog-Cookbooks/tree/main/01_Installation/compose/lookuptables): this folder contains a few lookuptables that can be used by Graylog Data Adapters. The Folder is accessible for Windows machines via Samba Share (credentials are the same as for the WebUI).
- **/maxmind**: this folder contains the GeoIP databases to be used by the Graylog Geo-Location Processor.
- [**/nginx**](https://github.com/fjagwitz/Graylog-Cookbooks/tree/main/01_Installation/compose/nginx): this folder contains the nginx configuration files for the nginx container.
- **/nginx/ssl**: this folder contains the nginx certificates for https connections.
- **/notifications** _(must be owned by the user:group with the id 1100)_: this folder contains scripts being used when the "SCRIPT NOTIFICATION" feature (Enterprise) is tested.
- [**/prometheus**](https://github.com/fjagwitz/Graylog-Cookbooks/tree/main/01_Installation/compose/prometheus): this folder contains configuration data to get metrics from Graylog to Grafana.
- **/warehouse** _(must be owned by the user:group with the id 1100)_: this folder contains data that is prepared for requirement-driven ingestion (Data Routing).

**/opt/opensearch** _(must be owned by the user:group with the id 1000)_:

- **datanode[1-3]**: these folders contain the Opensearch Data. You can mount any remote storage to that folder.
- **searchable_snapshots**: these folders contain Opensearch searchable snapshots (Data Tiering).
