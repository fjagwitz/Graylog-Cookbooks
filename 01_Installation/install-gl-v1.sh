#!/bin/bash
installpath="/opt/installpath"

# Configure vm.max_map_count for Opensearch (https://opensearch.org/docs/2.13/install-and-configure/install-opensearch/index/#important-settings)
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf >/dev/null
sudo sysctl -p >/dev/null

# Create Environment Variables
environmentfile="/etc/environment"

echo "GL_GRAYLOG=\"/opt/graylog\"" | sudo tee -a ${environmentfile} >/dev/null 
source ${environmentfile}

echo "GL_GRAYLOG_COMPOSE_ENV=${GL_GRAYLOG}/.env" | sudo tee -a ${environmentfile} >/dev/null

echo "GL_GRAYLOG_ARCHIVES=\"${GL_GRAYLOG}/archives\"" | sudo tee -a ${environmentfile} >/dev/null
echo "GL_GRAYLOG_CONTENTPACKS=\"${GL_GRAYLOG}/contentpacks\"" | sudo tee -a ${environmentfile} >/dev/null
echo "GL_GRAYLOG_JOURNAL=\"${GL_GRAYLOG}/journal\"" | sudo tee -a ${environmentfile} >/dev/null
echo "GL_GRAYLOG_MAXMIND=\"${GL_GRAYLOG}/maxmind\"" | sudo tee -a ${environmentfile} >/dev/null
echo "GL_GRAYLOG_NGINX=\"${GL_GRAYLOG}/nginx\"" | sudo tee -a ${environmentfile} >/dev/null
echo "GL_GRAYLOG_NOTIFICATIONS=\"${GL_GRAYLOG}/notifications\"" | sudo tee -a ${environmentfile} >/dev/null
echo "GL_GRAYLOG_PROMETHEUS=\"${GL_GRAYLOG}/prometheus\"" | sudo tee -a ${environmentfile} >/dev/null

echo "GL_OPENSEARCH_DATA=\"/opt/opensearch\"" | sudo tee -a ${environmentfile} >/dev/null
source ${environmentfile}

# Create required Folders in the Filesystem
sudo mkdir -p ${installpath}
sudo mkdir -p ${GL_OPENSEARCH_DATA}/{datanode1,datanode2,datanode3}
sudo mkdir -p ${GL_GRAYLOG}/{archives,contentpacks,journal,maxmind,nginx,notifications,prometheus}

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
# Reusing credentials is not a best practice and CAN ONLY be done for testing purposes; feel free to adapt those values for your purposes
# Predefined Root / admin Password is: "Secr3t2024!"
# Create your own Secret by using for example: echo -n yourpassword | shasum -a 256 
echo "GRAYLOG_ROOT_PASSWORD_SHA2=\"dfd0ac1ed1ea5d28e136edcec863b3cd7c7d868827e161152abb8d367182b2b7\"" | sudo tee -a ${GL_GRAYLOG_COMPOSE_ENV} >/dev/null
# Create your own Secret by using for example: pwgen -N 1 -s 96
echo "GRAYLOG_PASSWORD_SECRET=\"ob4xd0sdLM2yY4dUVcLgV81fU7RiWoblgxCz03YmoKcdTnMFvhx9HTnvVg82ckfWOfCljQqvYdzT6Adgx1pf6Xp1CaIshEfj\"" | sudo tee -a ${GL_GRAYLOG_COMPOSE_ENV} >/dev/null
# This can be kept as-is, because Opensearch will not be available except inside the Docker Network
echo "GL_OPENSEARCH_INITIAL_ADMIN_PASSWORD=\"TbY1EjV5sfs!u9;I0@3%9m7i520g3s\"" | sudo tee -a ${GL_GRAYLOG_COMPOSE_ENV} >/dev/null

sudo rm -rf ${installpath}

# Start Graylog
sudo docker compose -f ${GL_GRAYLOG}/docker-compose.yaml up -d --quiet-pull