#!/bin/bash
echo "[INFO] - PREPARING THE SYSTEM "
# Installing additional Tools on Ubuntu
sudo apt-get -qq install apt-utils vim git jq pwgen < /dev/null > /dev/null


# Check Minimum Requirements on Linux Server
numberCores=$(cat /proc/cpuinfo | grep processor | wc -l)
randomAccessMemory=$(grep MemTotal /proc/meminfo | awk '{print $2/1024 }' | awk -F'.' '{print $1 }')
operatingSystem=$(lsb_release -a | grep Distributor | awk -F":" '{print $2}' | xargs)

if [[ "$operatingSystem" == Ubuntu ]]
then
  echo "[INFO] - OPERATING SYSTEM CHECK SUCCESSFUL: $(lsb_release -a | grep Description | awk -F":" '{print $2}' | xargs) "
else
  echo "[INFO] - OPERATING SYSTEM CHECK FAILED: $(lsb_release -a | grep Description | awk -F":" '{print $2}' | xargs) "
  exit
fi

if [[ $numberCores -lt 8 ]]
then
  echo "[INFO] - THIS SYSTEM NEEDS AT LEAST 8 CPU CORES - EXIT "
  exit
else
  echo "[INFO] - CPU CHECK SUCCESSFUL: $numberCores CORES "
fi

if [[ $randomAccessMemory -lt 32000 ]]
then
  echo "[INFO] - THIS SYSTEM NEEDS AT LEAST 32 GB MEMORY - EXIT "
  exit
else
  echo "[INFO] - MEMORY CHECK SUCCESSFUL: $randomAccessMemory MB "
fi

if [[ $(command -v docker) -ne "" ]]
then
  echo "[INFO] - DOCKER CHECK SUCCESSFUL, CONTINUE "
else
  echo "[INFO] - DOCKER CHECK FAILED, WILL BE INSTALLED NOW "
  wget -q https://raw.githubusercontent.com/fjagwitz/Graylog-Cookbooks/main/01_Installation/install-docker-v1.sh 
  chmod +x ./install-docker-v1.sh
  ./install-docker-v1.sh
fi

# Configure temporary installpath
installpath="/tmp/graylog"

# Configure vm.max_map_count for Opensearch (https://opensearch.org/docs/2.13/install-and-configure/install-opensearch/index/#important-settings)
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf > /dev/null
sudo sysctl -p > /dev/null

# Create Environment Variables
environmentfile="/etc/environment"

echo "[INFO] - GRAYLOG INSTALLATION ABOUT TO START "

echo "GL_GRAYLOG=\"/opt/graylog\"" | sudo tee -a ${environmentfile} > /dev/null 
source ${environmentfile}

echo "GL_GRAYLOG_COMPOSE_ENV=${GL_GRAYLOG}/.env" | sudo tee -a ${environmentfile} > /dev/null

echo "GL_GRAYLOG_ARCHIVES=\"${GL_GRAYLOG}/archives\"" | sudo tee -a ${environmentfile} > /dev/null
echo "GL_GRAYLOG_CONTENTPACKS=\"${GL_GRAYLOG}/contentpacks\"" | sudo tee -a ${environmentfile} > /dev/null
echo "GL_GRAYLOG_JOURNAL=\"${GL_GRAYLOG}/journal\"" | sudo tee -a ${environmentfile} > /dev/null
echo "GL_GRAYLOG_LOOKUPTABLES=\"${GL_GRAYLOG}/lookuptables\"" | sudo tee -a ${environmentfile} > /dev/null
echo "GL_GRAYLOG_MAXMIND=\"${GL_GRAYLOG}/maxmind\"" | sudo tee -a ${environmentfile} > /dev/null
echo "GL_GRAYLOG_NGINX=\"${GL_GRAYLOG}/nginx\"" | sudo tee -a ${environmentfile} > /dev/null
echo "GL_GRAYLOG_NOTIFICATIONS=\"${GL_GRAYLOG}/notifications\"" | sudo tee -a ${environmentfile} > /dev/null
echo "GL_GRAYLOG_PROMETHEUS=\"${GL_GRAYLOG}/prometheus\"" | sudo tee -a ${environmentfile} > /dev/null

echo "GL_OPENSEARCH_DATA=\"/opt/opensearch\"" | sudo tee -a ${environmentfile} > /dev/null
source ${environmentfile}

# Create Secrets
GL_ 

# Create required Folders in the Filesystem
sudo mkdir -p ${installpath}
sudo mkdir -p ${GL_OPENSEARCH_DATA}/{datanode1,datanode2,datanode3}
sudo mkdir -p ${GL_GRAYLOG}/{archives,contentpacks,lookuptables,journal,maxmind,nginx,notifications,prometheus}

# Set Folder permissions
sudo chown -R 1000:1000 ${GL_OPENSEARCH_DATA}
sudo chown -R 1100:1100 ${GL_GRAYLOG_ARCHIVES} ${GL_GRAYLOG_JOURNAL} ${GL_GRAYLOG_NOTIFICATIONS}

# Download Maxmind Files (https://github.com/P3TERX/GeoLite.mmdb)
sudo wget -qP ${GL_GRAYLOG_MAXMIND} https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-ASN.mmdb 
sudo wget -qP ${GL_GRAYLOG_MAXMIND} https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb 
sudo wget -qP ${GL_GRAYLOG_MAXMIND} https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb 

# Cloning Git Repo containing prepared content
sudo git clone -q https://github.com/fjagwitz/Graylog-Cookbooks.git ${installpath}

# Copy Files into the proper directories
sudo cp ${installpath}/01_Installation/compose/nginx/*.conf ${GL_GRAYLOG_NGINX}
sudo cp ${installpath}/01_Installation/compose/nginx/ssl ${GL_GRAYLOG_NGINX} -R
sudo cp ${installpath}/01_Installation/compose/docker-compose.yaml ${GL_GRAYLOG}
sudo cp ${installpath}/01_Installation/compose/env.example ${GL_GRAYLOG}/.env
sudo cp ${installpath}/01_Installation/compose/prometheus/* ${GL_GRAYLOG_PROMETHEUS}

# Add Environment Variables for Docker Compose 
echo "Please add the central Administration Password: "
read GL_GRAYLOG_PASSWORD

echo "GRAYLOG_ROOT_PASSWORD_SHA2=$(echo ${GL_GRAYLOG_PASSWORD} | shasum -a 256 | awk '{print $1}')" | sudo tee -a ${GL_GRAYLOG_COMPOSE_ENV} > /dev/null
echo "GRAYLOG_PASSWORD_SECRET=$(pwgen -N 1 -s 96)" | sudo tee -a ${GL_GRAYLOG_COMPOSE_ENV} > /dev/null

# This can be kept as-is, because Opensearch will not be available except inside the Docker Network
echo "GL_OPENSEARCH_INITIAL_ADMIN_PASSWORD=\"TbY1EjV5sfs!u9;I0@3%9m7i520g3s\"" | sudo tee -a ${GL_GRAYLOG_COMPOSE_ENV} > /dev/null

sudo rm -rf ${installpath}

# Start Graylog Stack
echo "[INFO] - GRAYLOG CONTAINERS BEING PULLED - HANG ON, CAN TAKE A WHILE "
sudo docker compose -f ${GL_GRAYLOG}/docker-compose.yaml up -d --quiet-pull > /dev/null
clear

echo "[INFO] - VALIDATING GRAYLOG INSTALLATION, WAIT FOR ANOTHER FEW SECONDS "
sleep 90s

echo "[INFO] - USER: \"admin\" || PASSWORD: $(cat /opt/graylog/docker-compose.yaml | grep "preconfigured value for ROOT_PASSWORD" | awk '{ print $17 }') || CLUSTER-ID: $(curl $(hostname)/api | jq '.cluster_id' | tr a-z A-Z) "