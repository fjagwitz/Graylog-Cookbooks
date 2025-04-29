#!/bin/bash
echo "[INFO] - PREPARING THE SYSTEM FOR GRAYLOG 6.1"

# Request System Credentials
read -p "[INPUT] - Please add the name of your central Administration User (must not exist in /etc/passwd) [admin]: " GL_GRAYLOG_ADMIN
GL_GRAYLOG_ADMIN=${GL_GRAYLOG_ADMIN:-admin}
read -p "[INPUT] - Please add the central Administration Password [MyP@ssw0rd]: "$'\n' -s GL_GRAYLOG_PASSWORD
GL_GRAYLOG_PASSWORD=${GL_GRAYLOG_PASSWORD:-MyP@ssw0rd}
read -p "[INPUT] - Please add the fqdn of your Graylog Instance [eval.graylog.local]: " GL_GRAYLOG_ADDRESS
GL_GRAYLOG_ADDRESS=${GL_GRAYLOG_ADDRESS:-eval.graylog.local}
read -p "[INPUT] - Please add the folder where you want Graylog to be installed [/opt]: " GL_GRAYLOG_FOLDER
GL_GRAYLOG_FOLDER=${GL_GRAYLOG_FOLDER:-/opt}
read -p "[INPUT] - Please add the Graylog Version you want to install (Opensource / Enterprise) [Enterprise]: " GL_GRAYLOG_VERSION
GL_GRAYLOG_VERSION=${GL_GRAYLOG_VERSION:-enterprise}

# Check Minimum Requirements on Linux Server
numberCores=$(cat /proc/cpuinfo | grep processor | wc -l)
randomAccessMemory=$(printf '%.*f\n' 0 $(grep MemTotal /proc/meminfo | awk '{print $2/1024 }' | awk -F'.' '{print $1 }'))
operatingSystem=$(lsb_release -d | awk -F":" '{print $2}' | awk -F" " '{print $1}' | xargs)
connectionTest=$(curl -ILs https://github.com --connect-timeout 7 | head -n1 )

echo "[INFO] - VERIFYING INTERNET CONNECTION"
if [ "${connectionTest}" != "" ]
then
  echo "[INFO] - INTERNET CONNECTION OK "
else
  echo "[ERROR] - INTERNET CONNECTION NOT ACTIVE, CHECK YOUR PROXY SETTINGS - EXITING "
  exit
fi

echo "[INFO] - CHECKING OPERATING SYSTEM "
if [[ "$operatingSystem" == Ubuntu ]]
then
  echo "[INFO] - OPERATING SYSTEM CHECK SUCCESSFUL: $(lsb_release -d | awk -F":" '{print $2}' | awk -F" " '{print $1}' | xargs) "
else
  echo "[ERROR] - OPERATING SYSTEM CHECK FAILED: $(lsb_release -d | awk -F":" '{print $2}' | awk -F" " '{print $1}' | xargs) "
  exit
fi

echo "[INFO] - CHECKING CPU CORES "
if [[ $numberCores -lt 8 ]]
then
  echo "[ERROR] - THIS SYSTEM NEEDS AT LEAST 8 CPU CORES - EXITING "
  exit
else
  echo "[INFO] - CPU CHECK SUCCESSFUL: $numberCores CORES "
fi

echo "[INFO] - CHECKING CPU FLAGS "
if [[ $(lscpu | grep Flags | grep avx) == "" ]]
then
  echo "[ERROR] - THIS SYSTEM NEEDS A CPU WITH AVX FLAGS - EXITING "
  exit
else
  echo "[INFO] - CPU CHECK SUCCESSFUL: AVX FLAGS PRESENT "
fi

echo "[INFO] - CHECKING MEMORY "
if [[ $randomAccessMemory -lt 32000 ]]
then
  echo "[ERROR] - THIS SYSTEM NEEDS AT LEAST 32 GB MEMORY - EXITING "
  exit
else
  echo "[INFO] - MEMORY CHECK SUCCESSFUL: $randomAccessMemory MB "
fi

# Installing additional Tools on Ubuntu
echo "[INFO] - INSTALL ADDITIONAL TOOLS "
sudo apt-get -qq install vim git jq tcpdump pwgen samba acl 2>/dev/null >/dev/null
installcheck1=$(apt list --installed 2>/dev/null | grep samba)
connectionstate="1"

if [ "$installcheck1" == "" ]
then
  aptproxyconf="/etc/apt/apt.conf.d/99_proxy.conf"
  connectionstate="0"
  echo "[INFO] - ADDING APT PROXY CONFIG FROM ENVIRONMENT "
  echo "Acquire::http::Proxy \"$HTTP_PROXY\";" | sudo tee -a $aptproxyconf >/dev/null
  echo "Acquire::https::Proxy \"$HTTPS_PROXY\";" | sudo tee -a $aptproxyconf >/dev/null
  sudo apt-get -qq install vim git jq tcpdump pwgen samba acl 2>/dev/null >/dev/null
fi

installcheck2=$(apt list --installed 2>/dev/null | grep samba)

if [ "$installcheck2" == "" ]
then
  echo "[ERROR] - APT PACKAGE INSTALLATION FAILED - EXITING "
  exit 
fi

if [[ "$(command -v docker)" == "/usr/bin/docker" ]]; 
then
  echo "[INFO] - DOCKER CHECK SUCCESSFUL, CONTINUE "
else
  echo "[INFO] - DOCKER CHECK FAILED, WILL BE INSTALLED NOW "
  # Removing preconfigured Docker Installation from Ubuntu (just in case)
  echo "[INFO] - DOCKER CLEANUP "
  for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get -qq remove $pkg 2>/dev/null >/dev/null; done

  # Adding Docker Repository
  echo "[INFO] - ADDING DOCKER REPOSITORY "
  sudo apt-get -qq install ca-certificates curl 2>/dev/null >/dev/null
  sudo install -m 0755 -d /etc/apt/keyrings > /dev/null
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc > /dev/null
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  echo   "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu   $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |   sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get -qq update 2>/dev/null >/dev/null

  # Installing Docker on Ubuntu
  echo "[INFO] - DOCKER INSTALLATION "
  sudo apt-get -qq install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null >/dev/null

  # Checking Docker Installation Success
  if [[ "$(command -v docker)" == "/usr/bin/docker" ]]
  then
    echo "[INFO] - DOCKER SUCCESSFULLY INSTALLED, CONTINUE "
  else
    echo "[ERROR] - DOCKER INSTALLATION FAILED, EXITING"
    exit
  fi
fi

# Adding current User to Docker Admin Group
sudo usermod -aG docker $USER

# Configuring Docker Logging Settings
# echo "[INFO] - CONFIGURING DOCKER LOGGING "
# echo "{\"log-driver\": \"gelf\",\"log-opts\": {\"gelf-address\": \"udp://$(hostname):9900\"}}" | sudo tee -a /etc/docker/daemon.json >/dev/null 
# sudo service docker restart

# Configuring Docker Proxy Settings
if [ "$connectionstate" == "0" ]
then
  echo "{ \"proxies\": { \"http-proxy\": \"$HTTP_PROXY\", \"https-proxy\": \"$HTTPS_PROXY\",\"no-proxy\": \"$NO_PROXY\" } }" | sudo tee -a /etc/docker/daemon.json >/dev/null    
  sudo service docker stop 2>/dev/null >/dev/null
  sleep 2
  sudo systemctl stop docker.socket 2>/dev/null >/dev/null
  sleep 3
  sudo systemctl start docker.socket 2>/dev/null >/dev/null
  sleep 2
  sudo service docker start 2>/dev/null >/dev/null
fi

# Configure vm.max_map_count for Opensearch (https://opensearch.org/docs/2.15/install-and-configure/install-opensearch/index/#important-settings)
echo "[INFO] - SET OPENSEARCH SETTINGS "
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf > /dev/null
sudo sysctl -p > /dev/null

# Configure temporary installpath
installpath="/tmp/graylog"
sudo mkdir -p ${installpath}

# Create Environment Variables
environmentfile="/etc/environment"

echo "[INFO] - GRAYLOG INSTALLATION ABOUT TO START "
echo "[INFO] - SET ENVIRONMENT VARIABLES "

GL_GRAYLOG="${GL_GRAYLOG_FOLDER}/graylog"
GL_COMPOSE_ENV="${GL_GRAYLOG}/.env"
GL_GRAYLOG_COMPOSE_ENV="${GL_GRAYLOG}/graylog1.env"

echo "GL_GRAYLOG_ARCHIVES=\"${GL_GRAYLOG}/archives\"" | sudo tee -a ${environmentfile} > /dev/null
echo "GL_GRAYLOG_DATALAKE=\"${GL_GRAYLOG}/datalake\"" | sudo tee -a ${environmentfile} > /dev/null
echo "GL_GRAYLOG_CONTENTPACKS=\"${GL_GRAYLOG}/contentpacks\"" | sudo tee -a ${environmentfile} > /dev/null
echo "GL_GRAYLOG_JOURNAL=\"${GL_GRAYLOG}/journal\"" | sudo tee -a ${environmentfile} > /dev/null
echo "GL_GRAYLOG_LOOKUPTABLES=\"${GL_GRAYLOG}/lookuptables\"" | sudo tee -a ${environmentfile} > /dev/null
echo "GL_GRAYLOG_MAXMIND=\"${GL_GRAYLOG}/maxmind\"" | sudo tee -a ${environmentfile} > /dev/null
echo "GL_GRAYLOG_NGINX1=\"${GL_GRAYLOG}/nginx1\"" | sudo tee -a ${environmentfile} > /dev/null
echo "GL_GRAYLOG_NGINX2=\"${GL_GRAYLOG}/nginx2\"" | sudo tee -a ${environmentfile} > /dev/null
echo "GL_GRAYLOG_NOTIFICATIONS=\"${GL_GRAYLOG}/notifications\"" | sudo tee -a ${environmentfile} > /dev/null
echo "GL_GRAYLOG_PROMETHEUS=\"${GL_GRAYLOG}/prometheus\"" | sudo tee -a ${environmentfile} > /dev/null

echo "GL_OPENSEARCH_DATA=\"${GL_GRAYLOG_FOLDER}/opensearch\"" | sudo tee -a ${environmentfile} > /dev/null
source ${environmentfile}

# Create required Folders in the Filesystem
echo "[INFO] - CREATE FOLDERS "
sudo mkdir -p ${GL_OPENSEARCH_DATA}/{datanode1,datanode2,datanode3,searchable_snapshots}
sudo mkdir -p ${GL_GRAYLOG}/{archives,contentpacks,lookuptables,journal,maxmind,nginx1,nginx2,notifications,prometheus,datalake}

# Set Folder permissions
echo "[INFO] - SET FOLDER PERMISSIONS "
sudo chown -R 1000:1000 ${GL_OPENSEARCH_DATA}
sudo chown -R 1100:1100 ${GL_GRAYLOG_ARCHIVES} ${GL_GRAYLOG_DATALAKE} ${GL_GRAYLOG_JOURNAL} ${GL_GRAYLOG_NOTIFICATIONS}

# Download Maxmind Files (https://github.com/P3TERX/GeoLite.mmdb)
echo "[INFO] - DOWNLOAD MAXMIND DATABASES "
sudo curl --output-dir ${GL_GRAYLOG_MAXMIND} -LOs https://git.io/GeoLite2-ASN.mmdb
# OR use https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-ASN.mmdb 
sudo curl --output-dir ${GL_GRAYLOG_MAXMIND} -LOs https://git.io/GeoLite2-City.mmdb
# OR use https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb 
sudo curl --output-dir ${GL_GRAYLOG_MAXMIND} -LOs https://git.io/GeoLite2-Country.mmdb
# OR use https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb 

# Cloning Git Repo containing prepared content
echo "[INFO] - CLONE GIT REPO "
#sudo git clone -q https://github.com/fjagwitz/Graylog-Cookbooks.git  ${installpath}
sudo git clone -q --single-branch --branch Graylog-6.2 https://github.com/fjagwitz/Graylog-Cookbooks.git ${installpath}

# Copy Files from Git Repo into the proper directories
echo "[INFO] - POPULATE FOLDERS FROM GIT REPO CONTENT "
sudo cp ${installpath}/01_Installation/compose/nginx1/*.conf ${GL_GRAYLOG_NGINX1}
sudo cp ${installpath}/01_Installation/compose/nginx1/ssl ${GL_GRAYLOG_NGINX1} -R
sudo cp ${installpath}/01_Installation/compose/nginx2/*.conf ${GL_GRAYLOG_NGINX2}
sudo cp ${installpath}/01_Installation/compose/docker-compose.yaml ${GL_GRAYLOG}
sudo cp ${installpath}/01_Installation/compose/env.example ${GL_GRAYLOG}/.env
sudo cp ${installpath}/01_Installation/compose/graylog.example ${GL_GRAYLOG}/graylog1.env
sudo cp ${installpath}/01_Installation/compose/prometheus/* ${GL_GRAYLOG_PROMETHEUS}
sudo cp ${installpath}/01_Installation/compose/lookuptables/* ${GL_GRAYLOG_LOOKUPTABLES}
sudo cp ${installpath}/01_Installation/compose/contentpacks/* ${GL_GRAYLOG_CONTENTPACKS}

# This can be kept as-is, because Opensearch will not be available from outside the Docker Network
echo "GL_OPENSEARCH_INITIAL_ADMIN_PASSWORD=\"TbY1EjV5sfs!u9;I0@3%9m7i520g3s\"" | sudo tee -a ${GL_COMPOSE_ENV} > /dev/null

# The Graylog URI for additional Services like Grafana 
echo "GL_GRAYLOG_ADDRESS=\"${GL_GRAYLOG_ADDRESS}\"" | sudo tee -a ${GL_COMPOSE_ENV} > /dev/null

# The Graylog Version, in case one wants to use Graylog Open
if [[ ${GL_GRAYLOG_VERSION} != [Oo]pensource ]]
then
  GL_GRAYLOG_VERSION="graylog-enterprise"
else
  GL_GRAYLOG_VERSION="graylog"
fi
echo "GL_GRAYLOG_VERSION=\"${GL_GRAYLOG_VERSION}\"" | sudo tee -a ${GL_COMPOSE_ENV} > /dev/null

# Configure Docker Logging
echo "GL_GRAYLOG_LOG_TARGET = \"udp://$(hostname):9900\"" | sudo tee -a ${GL_COMPOSE_ENV} > /dev/null

# Adapt Variables in the graylog.env-file
echo "[INFO] - SET GRAYLOG DOCKER ENVIRONMENT VARIABLES "
GL_PASSWORD_SECRET=$(pwgen -N 1 -s 96)
GL_ROOT_PASSWORD_SHA2=$(echo ${GL_GRAYLOG_PASSWORD} | head -c -1 | shasum -a 256 | cut -d" " -f1)

sudo sed -i "s\GRAYLOG_ROOT_USERNAME = \"\"\GRAYLOG_ROOT_USERNAME = \"${GL_GRAYLOG_ADMIN}\"\g" ${GL_GRAYLOG_COMPOSE_ENV}
sudo sed -i "s\GRAYLOG_ROOT_PASSWORD_SHA2 = \"\"\GRAYLOG_ROOT_PASSWORD_SHA2 = \"${GL_ROOT_PASSWORD_SHA2}\"\g" ${GL_GRAYLOG_COMPOSE_ENV}
sudo sed -i "s\GRAYLOG_PASSWORD_SECRET = \"\"\GRAYLOG_PASSWORD_SECRET = \"${GL_PASSWORD_SECRET}\"\g" ${GL_GRAYLOG_COMPOSE_ENV}
sudo sed -i "s\GRAYLOG_HTTP_EXTERNAL_URI = \"\"\GRAYLOG_HTTP_EXTERNAL_URI = \"https://${GL_GRAYLOG_ADDRESS}/\"\g" ${GL_GRAYLOG_COMPOSE_ENV}
sudo sed -i "s\GRAYLOG_REPORT_RENDER_URI = \"\"\GRAYLOG_REPORT_RENDER_URI = \"http://${GL_GRAYLOG_ADDRESS}\"\g" ${GL_GRAYLOG_COMPOSE_ENV}
sudo sed -i "s\GRAYLOG_TRANSPORT_EMAIL_WEB_INTERFACE_URL = \"\"\GRAYLOG_TRANSPORT_EMAIL_WEB_INTERFACE_URL = \"https://${GL_GRAYLOG_ADDRESS}\"\g" ${GL_GRAYLOG_COMPOSE_ENV}

# Add HTTP_PROXY to graylog.env if that's required
if [ "$connectionstate" == "0" ]
then
  sudo sed -i "s\GRAYLOG_HTTP_PROXY_URI = \"\"\GRAYLOG_HTTP_PROXY_URI = \"$HTTP_PROXY\"\g" ${GL_GRAYLOG_COMPOSE_ENV}
fi

# Install Samba to make local Data Adapters accessible from Windows
echo "[INFO] - CONFIGURE FILESHARES "
sudo chmod 666 ${GL_GRAYLOG_LOOKUPTABLES}/*
sudo adduser ${GL_GRAYLOG_ADMIN} --system < /dev/null > /dev/null
sudo setfacl -m u:${GL_GRAYLOG_ADMIN}:rwx ${GL_GRAYLOG_LOOKUPTABLES}
sudo mv /etc/samba/smb.conf /etc/samba/smb.conf.bak
sudo mv ${installpath}/01_Installation/compose/samba/smb.conf /etc/samba/smb.conf
echo -e "${GL_GRAYLOG_PASSWORD}\n${GL_GRAYLOG_PASSWORD}" | sudo smbpasswd -a -s ${GL_GRAYLOG_ADMIN} > /dev/null
sudo sed -i -e "s/valid users = GLADMIN/valid users = ${GL_GRAYLOG_ADMIN}/g" /etc/samba/smb.conf 
sudo service smbd restart

# Installation Cleanup
sudo rm -rf ${installpath}
sudo rm -rf ${aptproxyconf}

# Start Graylog Stack
echo "[INFO] - PULL GRAYLOG CONTAINERS - HANG ON, CAN TAKE A WHILE "
sudo docker compose -f ${GL_GRAYLOG}/docker-compose.yaml pull -d --quiet-pull 2>/dev/null >/dev/null

echo "[INFO] - START GRAYLOG STACK - HANG ON, CAN TAKE A WHILE "
sudo docker compose -f ${GL_GRAYLOG}/docker-compose.yaml up -d --quiet-pull 2>/dev/null >/dev/null

echo "[INFO] - VALIDATE GRAYLOG INSTALLATION - HANG ON, CAN TAKE A WHILE "
sleep 5s

while [[ $(curl -s http://$(hostname)/api/system/lbstatus) != "ALIVE" ]]
do
  echo "[INFO] - WAIT FOR THE SYSTEM TO COME UP "
  sleep 10s
done

echo "[INFO] - FINALIZE SYSTEM CONFIGURATION "

# Adding Inputs to make sure Ports map to Nginx configuration
# Beats Input for Winlogbeat, Auditbeat, Filebeat
curl -s http://$(hostname)/api/system/inputs -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: \$\(hostname\)" -H 'Content-Type: application/json' -d '{ "global": true, "title": "Port 5044 Beats | Evaluation Input", "type": "org.graylog.plugins.beats.Beats2Input", "configuration": { "recv_buffer_size": 262144, "port": 5044, "number_worker_threads": 2, "charset_name": "UTF-8", "bind_address": "0.0.0.0" }}' 2>/dev/null >/dev/null

# Beats Input for Winlogbeat, Auditbeat, Filebeat
curl -s http://$(hostname)/api/system/inputs -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: \$\(hostname\)" -H 'Content-Type: application/json' -d '{ "global": true, "title": "Port 5045 Beats | Evaluation Input", "type": "org.graylog.plugins.beats.Beats2Input", "configuration": { "recv_buffer_size": 262144, "port": 5045, "number_worker_threads": 2, "charset_name": "UTF-8", "bind_address": "0.0.0.0" }}' 2>/dev/null >/dev/null

# Syslog UDP Input for Network Devices
curl -s http://$(hostname)/api/system/inputs -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: \$\(hostname\)" -H 'Content-Type: application/json' -d '{ "global": true, "title": "Port 514 UDP Syslog | Evaluation Input", "type": "org.graylog2.inputs.syslog.udp.SyslogUDPInput", "configuration": { "recv_buffer_size": 262144, "port": 1514, "number_worker_threads": 2, "charset_name": "UTF-8", "bind_address": "0.0.0.0" }}' 2>/dev/null >/dev/null

# Syslog TCP Input for Network Devices
curl -s http://$(hostname)/api/system/inputs -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: \$\(hostname\)" -H 'Content-Type: application/json' -d '{ "global": true, "title": "Port 514 TCP Syslog | Evaluation Input", "type": "org.graylog2.inputs.syslog.tcp.SyslogTCPInput", "configuration": { "recv_buffer_size": 262144, "port": 1514, "number_worker_threads": 2, "charset_name": "UTF-8", "bind_address": "0.0.0.0" }}' 2>/dev/null >/dev/null

# GELF TCP Input for NXLog
curl -s http://$(hostname)/api/system/inputs -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: \$\(hostname\)" -H 'Content-Type: application/json' -d '{ "global": true, "title": "Port 12201 TCP GELF | Evaluation Input", "type": "org.graylog2.inputs.gelf.tcp.GELFTCPInput", "configuration": { "recv_buffer_size": 262144, "port": 12201, "number_worker_threads": 2, "charset_name": "UTF-8", "bind_address": "0.0.0.0" }}' 2>/dev/null >/dev/null

# GELF UDP Input for NXLog
curl -s http://$(hostname)/api/system/inputs -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: \$\(hostname\)" -H 'Content-Type: application/json' -d '{ "global": true, "title": "Port 12201 UDP GELF | Evaluation Input", "type": "org.graylog2.inputs.gelf.udp.GELFUDPInput", "configuration": { "recv_buffer_size": 262144, "port": 12201, "number_worker_threads": 2, "charset_name": "UTF-8", "bind_address": "0.0.0.0" }}' 2>/dev/null >/dev/null
      
# RAW TCP Input
curl -s http://$(hostname)/api/system/inputs -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: \$\(hostname\)" -H 'Content-Type: application/json' -d '{ "global": true, "title": "Port 5555 TCP RAW | Evaluation Input", "type": "org.graylog2.inputs.raw.tcp.RawTCPInput", "configuration": { "recv_buffer_size": 262144, "port": 5555, "number_worker_threads": 2, "charset_name": "UTF-8", "bind_address": "0.0.0.0" }}' 2>/dev/null >/dev/null
    
# RAW UDP Input
curl -s http://$(hostname)/api/system/inputs -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: \$\(hostname\)" -H 'Content-Type: application/json' -d '{ "global": true, "title": "Port 5555 UDP RAW | Evaluation Input", "type": "org.graylog2.inputs.raw.udp.RawUDPInput", "configuration": { "recv_buffer_size": 262144, "port": 5555, "number_worker_threads": 2, "charset_name": "UTF-8", "bind_address": "0.0.0.0" }}' 2>/dev/null >/dev/null

# Fortinet Syslog TCP Input
curl -s http://$(hostname)/api/system/inputs -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: \$\(hostname\)" -H 'Content-Type: application/json' -d '{ "global": true, "title": "Port 5556 TCP Fortinet | Evaluation Input", "type": "org.graylog2.inputs.raw.tcp.RawTCPInput", "configuration": { "recv_buffer_size": 262144, "port": 5556, "number_worker_threads": 2, "charset_name": "UTF-8", "bind_address": "0.0.0.0" }}' 2>/dev/null >/dev/null
    
# Fortinet Syslog UDP Input
curl -s http://$(hostname)/api/system/inputs -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: \$\(hostname\)" -H 'Content-Type: application/json' -d '{ "global": true, "title": "Port 5556 UDP Fortinet | Evaluation Input", "type": "org.graylog2.inputs.raw.udp.RawUDPInput", "configuration": { "recv_buffer_size": 262144, "port": 5556, "number_worker_threads": 2, "charset_name": "UTF-8", "bind_address": "0.0.0.0" }}' 2>/dev/null >/dev/null

# Stopping all Inputs to allow a controlled Log Source Onboarding
echo "[INFO] - STOPPING ALL INPUTS" 
for input in $(curl -s http://$(hostname)/api/cluster/inputstates -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X GET | jq -r '.[] | map(.) | .[].id'); do
  curl -s http://$(hostname)/api/cluster/inputstates/$input -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X DELETE -H "X-Requested-By: $(hostname)" -H 'Content-Type: application/json' 2>/dev/null >/dev/null
done

# GELF UDP Input for NXLog
GL_MONITORING_INPUT=$(curl -s http://$(hostname)/api/system/inputs -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: \$\(hostname\)" -H 'Content-Type: application/json' -d '{ "global": true, "title": "Port 9900 UDP GELF | Evaluation Input", "type": "org.graylog2.inputs.gelf.udp.GELFUDPInput", "configuration": { "recv_buffer_size": 262144, "port": 9900, "number_worker_threads": 2, "charset_name": "UTF-8", "bind_address": "0.0.0.0" }}'| jq '.id') 

# Creating FieldType Profile for Docker Logs from Graylog Evaluation Stack
GL_MONITORING_FIELD_TYPE_PROFILE=$(curl -s http://$(hostname)/api/system/indices/index_sets/profiles -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: $(hostname)" -H 'Content-Type: application/json' -d '{ "custom_field_mappings":[{ "field": "command", "type": "string" }, { "field": "container_name", "type": "string" }, { "field": "image_name", "type": "string" }, { "field": "container_name", "type": "string" }], "name": "Self Monitoring Messages (Evaluation)", "description": "Field Mappings for Self Monitoring Messages" }' | jq '.id')

# Creating Index for Docker Logs from Graylog Evaluation Stack
GL_MONITORING_INDEX=$(curl -s http://$(hostname)/api/system/indices/index_sets -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: $(hostname)" -H 'Content-Type: application/json' -d "{\"shards\": 1, \"replicas\": 0, \"rotation_strategy_class\": \"org.graylog2.indexer.rotation.strategies.TimeBasedSizeOptimizingStrategy\", \"rotation_strategy\": {\"type\": \"org.graylog2.indexer.rotation.strategies.TimeBasedSizeOptimizingStrategyConfig\", \"index_lifetime_min\": \"P3D\", \"index_lifetime_max\": \"P14D\"}, \"retention_strategy_class\": \"org.graylog2.indexer.retention.strategies.DeletionRetentionStrategy\", \"retention_strategy\": { \"type\": \"org.graylog2.indexer.retention.strategies.DeletionRetentionStrategyConfig\", \"max_number_of_indices\": 20 }, \"data_tiering\": {\"type\": \"hot_only\", \"index_lifetime_min\": \"P3D\", \"index_lifetime_max\": \"P14D\"}, \"title\": \"Self Monitoring Messages (Evaluation)\", \"description\": \"Stores Evaluation System Self Monitoring Messages\", \"can_be_default\": false, \"index_prefix\": \"gl-self-monitoring\", \"index_analyzer\": \"standard\", \"index_optimization_max_num_segments\": 1, \"index_optimization_disabled\": false, \"field_type_refresh_interval\": 5000, \"field_type_profile\": ${GL_MONITORING_FIELD_TYPE_PROFILE}, \"use_legacy_rotation\": false, \"default\": false, \"writable\": true}" | jq '.id')

# Creating Stream for Docker Logs from Graylog Evaluation Stack
GL_MONITORING_STREAM=$(curl -s http://$(hostname)/api/streams -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: $(hostname)" -H 'Content-Type: application/json' -d "{ \"matching_type\": \"AND\", \"description\": \"Stream containing all self monitoring events created by Docker\", \"title\": \"System Self Monitoring (Evaluation)\", \"remove_matches_from_default_stream\": true, \"index_set_id\": ${GL_MONITORING_INDEX} }" | jq -r '.stream_id')

# Creating Stream Rule for Docker Logs from Graylog Evaluation Stack
curl -s http://$(hostname)/api/streams/${GL_MONITORING_STREAM}/rules -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: $(hostname)" -H 'Content-Type: application/json' -d "{ \"field\": \"gl2_source_input\", \"description\": \"Self Monitoring Logs\", \"type\": 1, \"inverted\": false, \"value\": ${GL_MONITORING_INPUT} }" 2>/dev/null >/dev/null

# Start Stream for Docker Logs from Graylog Evaluation Stack
curl -s http://$(hostname)/api/streams/${GL_MONITORING_STREAM}/resume -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: $(hostname)" 2>/dev/null >/dev/null

# Activating OTX Lists
curl -s http://$(hostname)/api/system/content_packs/daf6355e-2d5e-08d3-f9ba-44e84a43df1a/1/installations -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: $(hostname)" -H 'Content-Type: application/json' -d '{ "comment": "Activated for Evaluation" }' 2>/dev/null >/dev/null

# Activating Tor Exit Nodes Lists
curl -s http://$(hostname)/api/system/content_packs/9350a70a-8453-f516-7041-517b4df0b832/1/installations -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: $(hostname)" -H 'Content-Type: application/json' -d '{ "comment": "Activated for Evaluation" }' 2>/dev/null >/dev/null

# Activating Spamhaus Drop Lists
curl -s http://$(hostname)/api/system/content_packs/90be5e03-cb16-c802-6462-a244b4a342f3/1/installations -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: $(hostname)" -H 'Content-Type: application/json' -d '{ "comment": "Activated for Evaluation" }' 2>/dev/null >/dev/null

# Activating WHOIS Adapter
curl -s http://$(hostname)/api/system/content_packs/1794d39d-077f-7360-b92b-95411b05fbce/1/installations -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: $(hostname)" -H 'Content-Type: application/json' -d '{ "comment": "Activated for Evaluation" }' 2>/dev/null >/dev/null

# Activating the GeoIP Resolver Plugin
curl -s http://$(hostname)/api/system/cluster_config/org.graylog.plugins.map.config.GeoIpResolverConfig -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X PUT -H "X-Requested-By: $(hostname)" -H 'Content-Type: application/json' -d '{ "enabled":true,"enforce_graylog_schema":true,"db_vendor_type":"MAXMIND","city_db_path":"/etc/graylog/server/mmdb/GeoLite2-City.mmdb","asn_db_path":"/etc/graylog/server/mmdb/GeoLite2-ASN.mmdb","refresh_interval_unit":"DAYS","refresh_interval":14,"use_s3":false }' 2>/dev/null >/dev/null

# Activating the ThreatIntel Plugin
curl -s http://$(hostname)/api/system/cluster_config/org.graylog.plugins.threatintel.ThreatIntelPluginConfiguration -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" -X PUT -H "X-Requested-By: $(hostname)" -H 'Content-Type: application/json' -d '{"tor_enabled":true,"spamhaus_enabled":true,"abusech_ransom_enabled":false}'  2>/dev/null >/dev/null

## Reconfigure Grafana Credentials
curl -s http://admin:admin@$(hostname)/grafana/api/users/1 -H 'Content-Type:application/json' -X PUT -d "{ \"name\" : \"Evaluation Admin\", \"login\" : \"${GL_GRAYLOG_ADMIN}\" }" 2>/dev/null > /dev/null 
curl -s http://${GL_GRAYLOG_ADMIN}:admin@$(hostname)/grafana/api/admin/users/1/password -H 'Content-Type: application/json' -X PUT -d "{ \"password\" : \"$GL_GRAYLOG_PASSWORD\" }" 2>/dev/null > /dev/null 

## Configure Prometheus Connector 
curl -s http://${GL_GRAYLOG_ADMIN}:$GL_GRAYLOG_PASSWORD@$(hostname)/grafana/api/datasources -H 'Content-Type: application/json' -X POST -d '{ "name" : "prometheus", "type" : "prometheus", "url": "http://prometheus1:9090/prometheus", "access": "proxy", "readOnly" : false, "isDefault" : true, "basicAuth" : false }' 2>/dev/null > /dev/null 

echo ""
echo "[INFO] - SYSTEM READY FOR TESTING - FOR ADDITIONAL CONFIGURATIONS PLEASE DO REVIEW: ${GL_GRAYLOG}/graylog.env "
echo "[INFO] - CREDENTIALS STORED IN: ${GL_GRAYLOG}/your_graylog_credentials.txt "
echo ""
echo "[INFO] - URL: \"http(s)://${GL_GRAYLOG_ADDRESS}\" || CLUSTER-ID: $(curl -s $(hostname)/api | jq '.cluster_id' | tr a-z A-Z )" 
echo ""
echo "[INFO] - USER: \"${GL_GRAYLOG_ADMIN}\" || PASSWORD: \"${GL_GRAYLOG_PASSWORD}\" " | sudo tee ${GL_GRAYLOG}/your_graylog_credentials.txt 
echo ""

exit