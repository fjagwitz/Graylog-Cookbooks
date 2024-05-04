#!/bin/bash
installpath="$(pwd)/compose"

# Configure vm.max_map_count for Opensearch (https://opensearch.org/docs/2.13/install-and-configure/install-opensearch/index/#important-settings)
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Create Environment Variables
environmentfile="/etc/environment"

echo "GL_GRAYLOG=\"/opt/graylog\"" | sudo tee -a ${environmentfile}
source ${environmentfile}

echo "GL_GRAYLOG_ARCHIVES=\"${GL_GRAYLOG}/archives\"" | sudo tee -a ${environmentfile}
echo "GL_GRAYLOG_CONTENTPACKS=\"${GL_GRAYLOG}/contentpacks\"" | sudo tee -a ${environmentfile}
echo "GL_GRAYLOG_JOURNAL=\"${GL_GRAYLOG}/journal\"" | sudo tee -a ${environmentfile}
echo "GL_GRAYLOG_MAXMIND=\"${GL_GRAYLOG}/maxmind\"" | sudo tee -a ${environmentfile}
echo "GL_GRAYLOG_NGINX=\"${GL_GRAYLOG}/nginx\"" | sudo tee -a ${environmentfile}
echo "GL_GRAYLOG_NOTIFICATIONS=\"${GL_GRAYLOG}/notifications\"" | sudo tee -a ${environmentfile}
echo "GL_GRAYLOG_PROMETHEUS=\"${GL_GRAYLOG}/prometheus\"" | sudo tee -a ${environmentfile}

echo "GL_OPENSEARCH_DATA=\"/opt/opensearch\"" | sudo tee -a ${environmentfile}
echo "GL_OPENSEARCH_INITIAL_ADMIN_PASSWORD='TbY1EjV5sfs!u9;I0@3%9m7i520g3s'" | sudo tee -a ${environmentfile}
source ${environmentfile}

# Create required Folders in the Filesystem
sudo mkdir -p ${GL_OPENSEARCH_DATA}/{datanode1,datanode2,datanode3}
sudo mkdir -p ${GL_GRAYLOG_PROMETHEUS}
sudo mkdir -p ${GL_GRAYLOG}/{archives,contentpacks,journal,maxmind,nginx,notifications,prometheus}

# Set Folder permissions
sudo chown -R 1000:1000 ${GL_OPENSEARCH_DATA}
sudo chown -R 1100:1100 ${GL_GRAYLOG_ARCHIVES} ${GL_GRAYLOG_JOURNAL} ${GL_GRAYLOG_NOTIFICATIONS}

# Download Maxmind Files (https://github.com/P3TERX/GeoLite.mmdb)
sudo wget -P ${GL_GRAYLOG_MAXMIND} https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-ASN.mmdb
sudo wget -P ${GL_GRAYLOG_MAXMIND} https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb
sudo wget -P ${GL_GRAYLOG_MAXMIND} https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb

# Copy Files into the proper directories
sudo cp ${installpath}/nginx/*.conf ${GL_GRAYLOG_NGINX}
sudo cp ${installpath}/nginx/ssl ${GL_GRAYLOG_NGINX} -R
sudo cp ${installpath}/docker-compose.yaml ${GL_GRAYLOG}
sudo cp ${installpath}/env.example ${GL_GRAYLOG}/.env
sudo cp ${installpath}/prometheus/* ${GL_GRAYLOG_PROMETHEUS}

# Start Graylog
sudo docker compose -f ${GL_GRAYLOG}/docker-compose.yaml up -d


