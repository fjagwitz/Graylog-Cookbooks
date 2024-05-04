#!/bin/bash
installpath="$(pwd)/01_Installation/ubuntu/docker"
sourcerepo="https://github.com/fjagwitz/Graylog-Cookbooks.git"
targetrepo="/opt"

# Create required Folders in the Filesystem
sudo mkdir -p /opt/opensearch/{datanode1,datanode2,datanode3}
sudo mkdir -p /opt/graylog/{archives,contentpacks,journal,maxmind,nginx,notifications,prometheus}

# Create Environment Variables
environmentfile="/etc/environment"

echo "GL_OPENSEARCH_DATA=\"/opt/opensearch\"" | sudo tee -a ${environmentfile}
echo "GL_GRAYLOG_ARCHIVES=\"/opt/graylog/archives\"" | sudo tee -a ${environmentfile}
echo "GL_GRAYLOG_CONTENTPACKS=\"/opt/graylog/contentpacks\"" | sudo tee -a ${environmentfile}
echo "GL_GRAYLOG_JOURNAL=\"/opt/graylog/journal\"" | sudo tee -a ${environmentfile}
echo "GL_GRAYLOG_MAXMIND=\"/opt/graylog/maxmind\"" | sudo tee -a ${environmentfile}
echo "GL_GRAYLOG_NGINX=\"/opt/graylog/nginx\"" | sudo tee -a ${environmentfile}
echo "GL_GRAYLOG_NOTIFICATIONS=\"/opt/graylog/notifications\"" | sudo tee -a ${environmentfile}
echo "GL_GRAYLOG_PROMETHEUS=\"/opt/graylog/prometheus\"" | sudo tee -a ${environmentfile}

source ${environmentfile}

# Set Folder permissions
sudo chown -R 1100:1100 ${GL_GRAYLOG_ARCHIVES} ${GL_GRAYLOG_JOURNAL} ${GL_GRAYLOG_NOTIFICATIONS}

# Download Maxmind Files
sudo wget -P ${GL_GRAYLOG_MAXMIND} https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-ASN.mmdb
sudo wget -P ${GL_GRAYLOG_MAXMIND} https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb
sudo wget -P ${GL_GRAYLOG_MAXMIND} https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb

# Move Files into the proper directories
sudo mv ${installpath}/nginx/*.conf ${GL_GRAYLOG_NGINX}
sudo mv ${installpath}/docker-compose.yaml /opt/graylog
sudo mv ${installpath}/env.example /opt/graylog/.env


