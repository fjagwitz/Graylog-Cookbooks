#!/bin/bash
echo "[INFO] - PREPARING THE SYSTEM "

# Request System Credentials
read -p "[INPUT] - Please add the name of your central Administration User [admin]: " GL_GRAYLOG_ADMIN
GL_GRAYLOG_ADMIN=${GL_GRAYLOG_ADMIN:-admin}
read -p "[INPUT] - Please add the central Administration Password [MyP@ssw0rd]: "$'\n' -s GL_GRAYLOG_PASSWORD
GL_GRAYLOG_PASSWORD=${GL_GRAYLOG_PASSWORD:-MyP@ssw0rd}
read -p "[INPUT] - Please add the fqdn of your Graylog Instance [eval.graylog.local]: " GL_GRAYLOG_ADDRESS
GL_GRAYLOG_ADDRESS=${GL_GRAYLOG_ADDRESS:-eval.graylog.local}
read -p "[INPUT] - Where do you want Graylog to be installed [/opt]: " GL_GRAYLOG_FOLDER
GL_GRAYLOG_FOLDER=${GL_GRAYLOG_FOLDER:-/opt}

# Check Minimum Requirements on Linux Server
numberCores=$(cat /proc/cpuinfo | grep processor | wc -l)
randomAccessMemory=$(printf '%.*f\n' 0 $(grep MemTotal /proc/meminfo | awk '{print $2/1024 }' | awk -F'.' '{print $1 }'))
operatingSystem=$(lsb_release -a | grep Distributor | awk -F":" '{print $2}' | xargs)
connectionTest=$(curl -ILs https://github.com --connect-timeout 7 | head -n1 )

echo "[INFO] - VERIFYING INTERNET CONNECTION"
if [ "${connectionTest}" != "" ]
then
  echo "[INFO] - INTERNET CONNECTION OK "
else
  echo "[ERROR] - INTERNET CONNECTION NOT ACTIVE, CHECK YOUR PROXY SETTINGS - EXITING "
  exit
fi

echo "[INFO] - CHECKING MINIMUM REQUIREMENTS "
if [[ "$operatingSystem" == Ubuntu ]]
then
  echo "[INFO] - OPERATING SYSTEM CHECK SUCCESSFUL: $(lsb_release -a | grep Description | awk -F":" '{print $2}' | xargs) "
else
  echo "[ERROR] - OPERATING SYSTEM CHECK FAILED: $(lsb_release -a | grep Description | awk -F":" '{print $2}' | xargs) "
  exit
fi

if [[ $numberCores -lt 8 ]]
then
  echo "[ERROR] - THIS SYSTEM NEEDS AT LEAST 8 CPU CORES - EXITING "
  exit
else
  echo "[INFO] - CPU CHECK SUCCESSFUL: $numberCores CORES "
fi

if [[ $randomAccessMemory -lt 24576 ]]
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

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get -qq update 2>/dev/null >/dev/null

  # Installing Docker on Ubuntu
  echo "[INFO] - DOCKER INSTALLATION "
  sudo apt-get -qq install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null >/dev/null

  # Configuring Proxy Settings
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

  # Checking Docker Installation Success
  if [[ "$(command -v docker)" == "/usr/bin/docker" ]]
  then
    echo "[INFO] - DOCKER SUCCESSFULLY INSTALLED, CONTINUE "
  else
    echo "[ERROR] - DOCKER INSTALLATION FAILED, EXITING"
    exit
  fi
fi

# Configure temporary installpath
installpath="/tmp/graylog"

# Configure vm.max_map_count for Opensearch (https://opensearch.org/docs/2.13/install-and-configure/install-opensearch/index/#important-settings)
echo "[INFO] - SET OPENSEARCH SETTINGS "
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf > /dev/null
sudo sysctl -p > /dev/null

# Create Environment Variables
environmentfile="/etc/environment"

echo "[INFO] - GRAYLOG INSTALLATION ABOUT TO START "
echo "[INFO] - SET ENVIRONMENT VARIABLES "

GL_COMPOSE_ENV="${GL_GRAYLOG_FOLDER}/graylog/.env"
GL_GRAYLOG_COMPOSE_ENV="${GL_GRAYLOG_FOLDER}/graylog/graylog1.env"

echo "GL_GRAYLOG_ARCHIVES=\"${GL_GRAYLOG_FOLDER}/graylog/archives\"" | sudo tee -a ${environmentfile} > /dev/null
echo "GL_GRAYLOG_CONTENTPACKS=\"${GL_GRAYLOG_FOLDER}/graylog/contentpacks\"" | sudo tee -a ${environmentfile} > /dev/null
echo "GL_GRAYLOG_JOURNAL=\"${GL_GRAYLOG_FOLDER}/graylog/journal\"" | sudo tee -a ${environmentfile} > /dev/null
echo "GL_GRAYLOG_LOOKUPTABLES=\"${GL_GRAYLOG_FOLDER}/graylog/lookuptables\"" | sudo tee -a ${environmentfile} > /dev/null
echo "GL_GRAYLOG_MAXMIND=\"${GL_GRAYLOG_FOLDER}/graylog/maxmind\"" | sudo tee -a ${environmentfile} > /dev/null
echo "GL_GRAYLOG_NGINX1=\"${GL_GRAYLOG_FOLDER}/graylog/nginx1\"" | sudo tee -a ${environmentfile} > /dev/null
echo "GL_GRAYLOG_NGINX2=\"${GL_GRAYLOG_FOLDER}/graylog/nginx2\"" | sudo tee -a ${environmentfile} > /dev/null
echo "GL_GRAYLOG_NOTIFICATIONS=\"${GL_GRAYLOG_FOLDER}/graylog/notifications\"" | sudo tee -a ${environmentfile} > /dev/null
echo "GL_GRAYLOG_PROMETHEUS=\"${GL_GRAYLOG_FOLDER}/graylog/prometheus\"" | sudo tee -a ${environmentfile} > /dev/null

source ${environmentfile}

# Create required Folders in the Filesystem
echo "[INFO] - CREATE FOLDERS "
sudo mkdir -p ${installpath}
sudo mkdir -p ${GL_GRAYLOG_FOLDER}/opensearch/{datanode1,datanode2,datanode3}
sudo mkdir -p ${GL_GRAYLOG_FOLDER}/graylog/{archives,contentpacks,lookuptables,journal,maxmind,nginx1,nginx2,notifications,prometheus}

# Set Folder permissions
echo "[INFO] - SET FOLDER PERMISSIONS "
sudo chown -R 1000:1000 ${GL_GRAYLOG_FOLDER}/opensearch
sudo chown -R 1100:1100 ${GL_GRAYLOG_ARCHIVES} ${GL_GRAYLOG_JOURNAL} ${GL_GRAYLOG_NOTIFICATIONS}

# Download Maxmind Files (https://github.com/P3TERX/GeoLite.mmdb)
echo "[INFO] - DOWNLOAD MAXMIND DATABASES "
sudo curl --output-dir ${GL_GRAYLOG_MAXMIND} -Os https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-ASN.mmdb 
sudo curl --output-dir ${GL_GRAYLOG_MAXMIND} -Os https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb 
sudo curl --output-dir ${GL_GRAYLOG_MAXMIND} -Os https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb 

# Cloning Git Repo containing prepared content
echo "[INFO] - CLONE GIT REPO "
sudo git clone -q https://github.com/fjagwitz/Graylog-Cookbooks.git ${installpath}

# Copy Files into the proper directories
echo "[INFO] - POPULATE FOLDERS FROM GIT REPO CONTENT "
sudo cp ${installpath}/01_Installation/compose/nginx1/*.conf ${GL_GRAYLOG_NGINX1}
sudo cp ${installpath}/01_Installation/compose/nginx1/ssl ${GL_GRAYLOG_NGINX1} -R
sudo cp ${installpath}/01_Installation/compose/nginx2/*.conf ${GL_GRAYLOG_NGINX2}
sudo cp ${installpath}/01_Installation/compose/docker-compose.yaml ${GL_GRAYLOG_FOLDER}/graylog
sudo cp ${installpath}/01_Installation/compose/env.example ${GL_GRAYLOG_FOLDER}/graylog/.env
sudo cp ${installpath}/01_Installation/compose/graylog.example ${GL_GRAYLOG_FOLDER}/graylog/graylog1.env
sudo cp ${installpath}/01_Installation/compose/prometheus/* ${GL_GRAYLOG_PROMETHEUS}
sudo cp ${installpath}/01_Installation/compose/lookuptables/* ${GL_GRAYLOG_LOOKUPTABLES}
sudo cp ${installpath}/01_Installation/compose/contentpacks/* ${GL_GRAYLOG_CONTENTPACKS}

# Add HTTP_PROXY to docker-compose.yaml
if [ "$connectionstate" == "0" ]
then
  sudo sed -i "s\GRAYLOG_HTTP_PROXY_URI: \"\"\GRAYLOG_HTTP_PROXY_URI: \"$HTTP_PROXY\"\g" ${GL_GRAYLOG_FOLDER}/graylog/docker-compose.yaml
fi

# This can be kept as-is, because Opensearch will not be available except inside the Docker Network
echo "GL_OPENSEARCH_INITIAL_ADMIN_PASSWORD=\"TbY1EjV5sfs!u9;I0@3%9m7i520g3s\"" | sudo tee -a ${GL_COMPOSE_ENV} > /dev/null


# Add Graylog Secrets to Docker .env-file
echo "[INFO] - SET SECRETS "
echo "GL_ROOT_USERNAME=\"$(echo ${GL_GRAYLOG_ADMIN})\"" | sudo tee -a ${GL_GRAYLOG_COMPOSE_ENV} > /dev/null
GL_ROOT_PASSWORD_SHA2=$(echo ${GL_GRAYLOG_PASSWORD} | head -c -1 | shasum -a 256 | cut -d" " -f1)
echo "GL_ROOT_PASSWORD_SHA2=\"${GL_ROOT_PASSWORD_SHA2}\"" | sudo tee -a ${GL_GRAYLOG_COMPOSE_ENV} > /dev/null
echo "GL_PASSWORD_SECRET=\"$(pwgen -N 1 -s 96)\"" | sudo tee -a ${GL_GRAYLOG_COMPOSE_ENV} > /dev/null

# Additional Graylog config data to guarantee minimum functionality
sudo sed -i "s\GRAYLOG_ROOT_USERNAME = \"\"\"\GRAYLOG_ROOT_USERNAME = \"${GL_GRAYLOG_ADMIN}\"\g" ${GL_GRAYLOG_COMPOSE_ENV}
sudo sed -i "s\GRAYLOG_ROOT_PASSWORD_SHA2 = \"\"\"\GRAYLOG_ROOT_PASSWORD_SHA2 = \"${GL_GRAYLOG_ADMIN}\"\g" ${GL_GRAYLOG_COMPOSE_ENV}
sudo sed -i "s\GRAYLOG_ROOT_PASSWORD = \"\"\"\GRAYLOG_ROOT_PASSWORD = \"${GL_GRAYLOG_PASSWORD}\"\g" ${GL_GRAYLOG_COMPOSE_ENV}
sudo sed -i "s\GRAYLOG_HTTP_EXTERNAL_URI = \"\"\"\GRAYLOG_HTTP_EXTERNAL_URI = \"${GL_GRAYLOG_ADDRESS}\"\g" ${GL_GRAYLOG_COMPOSE_ENV}

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
sudo docker compose -f ${GL_GRAYLOG_FOLDER}/graylog/docker-compose.yaml up -d --quiet-pull 2>/dev/null >/dev/null

echo "[INFO] - VALIDATE GRAYLOG INSTALLATION - HANG ON, CAN TAKE A WHILE "
sleep 5s

while [[ $(curl -s $(hostname)/api/system/lbstatus) != "ALIVE" ]]
do
  echo "[INFO] - WAIT FOR THE SYSTEM TO COME UP "
  sleep 10s
done

echo "[INFO] - FINALIZE CONFIGURATION "

# Activating the GeoIP Resolver Plugin
curl http://$(hostname)/api/system/cluster_config/org.graylog.plugins.map.config.GeoIpResolverConfig \
  -u "${GL_GRAYLOG_ADMIN}":"${GL_GRAYLOG_PASSWORD}" \
  -X PUT \
  -H "X-Requested-By: $(hostname)" \
  -H 'Content-Type: application/json' \
  -d '{ "enabled":true,"enforce_graylog_schema":true,"db_vendor_type":"MAXMIND","city_db_path":"/etc/graylog/server/mmdb/GeoLite2-City.mmdb","asn_db_path":"/etc/graylog/server/mmdb/GeoLite2-ASN.mmdb","refresh_interval_unit":"DAYS","refresh_interval":14,"use_s3":false }' 2>/dev/null >/dev/null

echo ""
echo "[INFO] - SYSTEM READY FOR TESTING - FOR ADDITIONAL CONFIGURATIONS PLEASE DO REVIEW: ${GL_GRAYLOG_FOLDER}/graylog/docker-compose.yaml "
echo "[INFO] - CREDENTIALS STORED IN: ${GL_GRAYLOG_FOLDER}/graylog/your_graylog_credentials.txt "
echo ""
echo "[INFO] - USER: \"${GL_GRAYLOG_ADMIN}\" || PASSWORD: \"${GL_GRAYLOG_PASSWORD}\" || CLUSTER-ID: $(curl -s $(hostname)/api | jq '.cluster_id' | tr a-z A-Z )" | tee ${GL_GRAYLOG_FOLDER}/graylog/your_graylog_credentials.txt
echo ""

exit
