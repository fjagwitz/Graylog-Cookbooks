#!/bin/bash
#
# title:             install-graylog.sh
# description:       Installs a complete Graylog Cluster for testing purposes
# author:            Friedrich von Jagwitz 
# email:             fvj@graylog.com
# date:              2025-11-11
# version:           1.0
# usage:             bash install-graylog.sh
# notes:             
#==============================================================================

###############################################################################
#
# Static Variables Definition

GRAYLOG_VERSION="7.0"
GRAYLOG_PATH="/opt/graylog"
GRAYLOG_COMPOSE="docker-compose.yaml"
GRAYLOG_SERVER_ENV="graylog.env"
GRAYLOG_DATABASE_ENV="opensearch.env"
GRAYLOG_ADMIN=""
GRAYLOG_PASSWORD=""
GRAYLOG_ADMIN_TOKEN="${1}"
GRAYLOG_FQDN=""
GRAYLOG_SIDECAR="graylog-sidecar"
GRAYLOG_LICENSE_ENTERPRISE=""
GRAYLOG_LICENSE_SECURITY=""

SCRIPT_DEPENDENCIES="dnsutils net-tools vim git jq tcpdump pwgen htop unzip curl ca-certificates" 
SYSTEM_PROXY=$(cat /etc/environment | grep -w http_proxy | cut -d "=" -f 2 | tr -d '"')
SYSTEM_CRONPATH="/etc/cron.d/graylog-stack"


###############################################################################
#
# Functions Definition

function_checkSnapshot () {

    read -p "[INPUT] - Please confirm that you created a Snapshot of the VM before running this Script [yes/no]: " SNAPSHOT_CREATED

    local SNAPSHOT_CREATED=${SNAPSHOT_CREATED:-no}

    if [[ ${SNAPSHOT_CREATED} != "yes" ]]
    then
        echo "[ERROR] - NO SNAPSHOT WAS CREATED, PLEASE CREATE ONE - EXITING" 
        exit
    fi 
}

function_defineAdminName () {

    while [[ ${VALID_ADMIN} != "true" ]]
    do
        read -p "[INPUT] - Please add the name of your central Administration User [admin]: " ADMIN_NAME
        
        local ADMIN_NAME=${ADMIN_NAME:-admin}
        local FORBIDDEN_USERNAMES=$(cat /etc/passwd | awk -F":" '{print $1}')
        
        if [[ ${ADMIN_NAME} =~ ^[A-Za-z0-9_-]{4,12}$ ]]
        then
            for USER_NAME in ${FORBIDDEN_USERNAMES}
            do
                if [[ ${ADMIN_NAME} == ${USER_NAME} ]]
                then                    
                    echo "[INFO] - A VALID USERNAME MUST NOT BE AVAILABLE ON THIS SYSTEM, TRY AGAIN" 
                    VALID_ADMIN="false"
                    break
                else
                    VALID_ADMIN="true"

                    # Set global Variable for Graylog Admin
                    GRAYLOG_ADMIN=${ADMIN_NAME}
                fi
            done
        else
            echo "[INFO] - A VALID USERNAME CONSISTS OF 4-12 LETTERS, TRY AGAIN" 
        fi
    done
}

function_defineAdminPassword () {
    
    local GRAYLOG_PASSWORD1="CanBeEveryPasswordFrom2025!"

    while [[ ${GRAYLOG_PASSWORD1} != ${GRAYLOG_PASSWORD2} ]]
    do
        read -p "[INPUT] - Please add the central Administration Password [MyP@ssw0rd]: "$'\n' -s GRAYLOG_PASSWORD_A
        local GRAYLOG_PASSWORD1=${GRAYLOG_PASSWORD_A:-MyP@ssw0rd}
        read -p "[INPUT] - Please confirm the central Administration Password: "$'\n' -s GRAYLOG_PASSWORD_B
        local GRAYLOG_PASSWORD2=${GRAYLOG_PASSWORD_B:-MyP@ssw0rd}     
    done

    GRAYLOG_PASSWORD=${GRAYLOG_PASSWORD1}
} 

function_getSystemFqdn () {

    local SYSTEM_IP=$(ip a | grep -v inet6 | grep inet | awk -F" " '{print $2}' | cut -f1 -d "/" | tr -d ' ')    
    local VALID_FQDN="false"

    while [[ ${VALID_FQDN} != "true" ]]
    do
        read -p "[INPUT] - Please add the fqdn of your Graylog Instance [eval.graylog.local]: " SYSTEM_FQDN
        local SYSTEM_FQDN=${SYSTEM_FQDN:-eval.graylog.local}
        local FQDN_IP=$(nslookup ${SYSTEM_FQDN} | grep -A3 answer | grep Address | awk -F":" '{print $2}' | tr -d ' ')

        for IP in ${SYSTEM_IP}
        do
            if [[ ${IP} == ${FQDN_IP} ]]
            then
                VALID_FQDN="true"
            fi
        done

        if [[ ${VALID_FQDN} != "true" ]]
        then
            read -p "[INPUT] - The FQDN you provided does not seem to be resolvable; continue anyway? [yes/no]: " CHECK_IGNORE
            local CHECK_IGNORE=${CHECK_IGNORE: no}
            
            if [[ ${CHECK_IGNORE} == "yes" ]]
            then
                echo "[WARN] - CONTINUE WITHOUT VALIDATED FQDN, EXPECTING PRODUCT ISSUES " 
                VALID_FQDN="true" 
            fi
        fi
    done

    # Set global Variable for Graylog FQDN
    GRAYLOG_FQDN=${SYSTEM_FQDN}
}

function_checkSystemRequirements () {

    local INTERNET_CONNECTIVITY=$(curl -ILs https://github.com --connect-timeout 7 | head -n1 | cut -d " " -f2)
    local OPERATING_SYSTEM=$(hostnamectl | grep -i "operating system" | cut -d " " -f3)
    local RANDOM_ACCESS_MEMORY=$(vmstat -s | grep "total memory" | grep -o [0-9]* | awk '{print int($0/1024/1024)+1}')
    local CPU_CORES_NUMBER=$(nproc)
    local CPU_REQUIRED_FLAGS=$(lscpu | grep -wio avx)
    local TOTAL_DISK_SPACE=$(df -BG --total | grep -w total | awk '{print $2}' | grep -oE [0-9]*)

    if [ ${OPERATING_SYSTEM,,} == "ubuntu" ] && [ ${RANDOM_ACCESS_MEMORY} -ge 32 ] && [ ${CPU_CORES_NUMBER} -ge 8 ] && [ ${CPU_REQUIRED_FLAGS,,} == "avx" ] && [ ${INTERNET_CONNECTIVITY} -eq 200 ] && [ ${TOTAL_DISK_SPACE} -ge 600 ]
    then
        echo "[INFO] - SYSTEM REQUIREMENTS CHECK SUCCESSFUL: 

                Operating System: ${OPERATING_SYSTEM}
                Storage         : ${TOTAL_DISK_SPACE} GB
                Memory          : ${RANDOM_ACCESS_MEMORY} GB
                CPU Cores       : ${CPU_CORES_NUMBER} vCPU
                CPU Flags       : ${CPU_REQUIRED_FLAGS^^} available
                Internet        : Available
                "
    else
        if [ ${INTERNET_CONNECTIVITY} -ne 200 ]
        then
            echo "[ERROR] - INTERNET IS NOT AVAILABLE FROM THIS MACHINE "
        fi
        if [ ${OPERATING_SYSTEM,,} != "ubuntu" ]
        then
            echo "[ERROR] - OPERATING SYSTEM MUST BE UBUNTU, BUT IS ${OPERATING_SYSTEM}" 
        fi
        if [ ${RANDOM_ACCESS_MEMORY} -lt 32 ]
        then
            echo "[ERROR] - MEMORY MUST BE AT LEAST 32 GB, BUT IS ONLY ${RANDOM_ACCESS_MEMORY} GB" 
        fi
        if [ ${CPU_CORES_NUMBER} -lt 8 ]
        then
            echo "[ERROR] - THE SYSTEM MUST HAVE AT LEAST 8 VCPU CORES, BUT HAS ONLY ${CPU_CORES_NUMBER}" 
        fi
        if [ ${CPU_REQUIRED_FLAGS^^} != "AVX" ]
        then
            echo "[ERROR] - THE CPU MUST SUPPORT THE AVX FLAG FOR RUNNING MONGODB, BUT DOES NOT" 
        fi
        if [ ${TOTAL_DISK_SPACE} -lt 600 ]
        then
            echo "[ERROR] - THE SYSTEM MUST HAVE AT LEAST 600GB STORAGE, BUT HAS ONLY ${TOTAL_DISK_SPACE} GB"
        fi
        exit
    fi
}

function_installScriptDependencies () {

    echo "[INFO] - PERFORM SYSTEM UPDATE "   
    sudo apt -qq update -y 2>/dev/null >/dev/null 
    sudo apt -qq upgrade -y 2>/dev/null >/dev/null
    echo "[INFO] - PERFORM SYSTEM CLEANUP "  
    sudo apt -qq autoremove -y 2>/dev/null >/dev/null
    for DEP in ${SCRIPT_DEPENDENCIES}
    do
        echo "[INFO] - INSTALL ADDITIONAL PACKAGE: ${DEP^^}"
        sudo apt -qq install -y ${DEP} 2>/dev/null >/dev/null
    done
}

function_installDocker () {

    local DOCKER_OS_PACKAGES="docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc"
    local DOCKER_CE_PACKAGES="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
    local DOCKER_URL="https://download.docker.com/linux/ubuntu"
    local DOCKER_KEY="/etc/apt/keyrings/docker.asc"

   
    if [[ "$(command -v docker)" == "" ]]
    then
        echo "[INFO] - REMOVE PREINSTALLED PACKAGES - DOCKER CLEANUP "
        for PKG in ${DOCKER_PACKAGES} 
        do 
            sudo apt-get -qq remove $PKG 2>/dev/null >/dev/null
        done

        # Adding Docker Repository
        echo "[INFO] - ADD DOCKER REPOSITORY TO APT SOURCES"
        sudo install -m 0755 -d /etc/apt/keyrings > /dev/null
        sudo curl -fsSL ${DOCKER_URL}/gpg -o ${DOCKER_KEY} > /dev/null
        sudo chmod a+r ${DOCKER_KEY}

        echo   "deb [arch=$(dpkg --print-architecture) signed-by=${DOCKER_KEY}] ${DOCKER_URL}   $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get -qq update 2>/dev/null >/dev/null

        # INSTALL Docker on Ubuntu
        for PKG in ${DOCKER_CE_PACKAGES}
        do 
            echo "[INFO] - INSTALL ADDITIONAL PACKAGE: ${PKG^^}"
            sudo apt -qq install -y ${PKG} 2>/dev/null >/dev/null
        done

        # Checking Docker Installation Success
        if [ "$(docker -v | cut -d " " -f1 )" == "Docker" ]
        then
            echo "[INFO] - DOCKER SUCCESSFULLY INSTALLED, CONTINUE "
        else
            echo "[ERROR] - DOCKER INSTALLATION FAILED, EXITING"
            exit
        fi

        sudo usermod -aG docker $USER
    fi
}

function_installGraylogStack () {

    local INSTALLPATH="/tmp/graylog"
    local FOLDERS_WITH_GRAYLOG_PERMISSIONS="archives datalake input_tls notifications"
    local GRAYLOG_ENV="${GRAYLOG_PATH}/${GRAYLOG_SERVER_ENV}"
    local DATABASE_ENV="${GRAYLOG_PATH}/${GRAYLOG_DATABASE_ENV}"
    local NGINX_HTTP_CONF="${GRAYLOG_PATH}/nginx1/http.conf"

    # Configure vm.max_map_count for Opensearch (https://opensearch.org/docs/2.15/install-and-configure/install-opensearch/index/#important-settings)
    echo "[INFO] - SET OPENSEARCH SETTINGS "
    echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf > /dev/null
    sudo sysctl -p > /dev/null

    sudo mkdir -p ${INSTALLPATH}

    # Create required Folders in the Filesystem
    echo "[INFO] - CREATE FOLDERS "
    sudo mkdir -p ${GRAYLOG_PATH}/{archives,assetdata,configuration,contentpacks,database/{datanode1,datanode2,datanode3,warm_tier},datalake,input_tls,logsamples,lookuptables,maxmind,nginx1,nginx2,notifications,prometheus,rootcerts,samba,sources/{scripts,binaries/{Graylog_Sidecar,Filebeat_Standalone,NXLog_CommunityEdition},other}}

    echo "[INFO] - CLONE GIT REPO "
    sudo git clone -q --single-branch --branch Graylog-${GRAYLOG_VERSION} https://github.com/fjagwitz/Graylog-Cookbooks.git ${INSTALLPATH}

    echo "[INFO] - POPULATE FOLDERS FROM GIT REPO CONTENT "
    local ITEMS=$(ls ${INSTALLPATH}/01_Installation/compose | xargs)

    for ITEM in ${ITEMS}
    do
        sudo cp -R ${INSTALLPATH}/01_Installation/compose/${ITEM} ${GRAYLOG_PATH}
    done

    # Start pulling Containers
    sudo docker compose -f ${GRAYLOG_PATH}/docker-compose.yaml pull --quiet-pull 2>/dev/null >/dev/null

    # Adapting Permissions for proper access by the Opensearch Containers (1000:1000)
    sudo chown -R 1000:1000 ${GRAYLOG_PATH}/database

    # Adapting Permissions for proper access by the Graylog Containers (1100:1100)
    for FOLDER in ${FOLDERS_WITH_GRAYLOG_PERMISSIONS}
    do
        sudo chown -R 1100:1100 ${GRAYLOG_PATH}/${FOLDER}
    done

    # Renaming Environment File for Graylog
    sudo mv ${GRAYLOG_PATH}/graylog.example ${GRAYLOG_PATH}/graylog.env

    # Populating Environment File for Opensearch
    echo "OPENSEARCH_INITIAL_ADMIN_PASSWORD = \"$(pwgen -N 1 -s 48)\"" | sudo tee -a ${DATABASE_ENV} > /dev/null
    echo "OPENSEARCH_JAVA_OPTS = \"-Xms4096m -Xmx4096m\"" | sudo tee -a ${DATABASE_ENV} > /dev/null

    # Populating Environment File for Graylog
    echo "[INFO] - SET GRAYLOG DOCKER ENVIRONMENT VARIABLES "
    local SYSTEM_PASSWORD_SECRET=$(pwgen -N 1 -s 96)
    local SYSTEM_ROOT_PASSWORD_SHA2=$(echo ${GRAYLOG_PASSWORD} | head -c -1 | shasum -a 256 | cut -d" " -f1)

    sudo sed -i "s\GRAYLOG_ROOT_USERNAME = \"\"\GRAYLOG_ROOT_USERNAME = \"${GRAYLOG_ADMIN}\"\g" ${GRAYLOG_ENV}
    sudo sed -i "s\GRAYLOG_ROOT_PASSWORD_SHA2 = \"\"\GRAYLOG_ROOT_PASSWORD_SHA2 = \"${SYSTEM_ROOT_PASSWORD_SHA2}\"\g" ${GRAYLOG_ENV}
    sudo sed -i "s\GRAYLOG_PASSWORD_SECRET = \"\"\GRAYLOG_PASSWORD_SECRET = \"${SYSTEM_PASSWORD_SECRET}\"\g" ${GRAYLOG_ENV}
    sudo sed -i "s\GRAYLOG_HTTP_EXTERNAL_URI = \"\"\GRAYLOG_HTTP_EXTERNAL_URI = \"https://${GRAYLOG_FQDN}/\"\g" ${GRAYLOG_ENV}
    sudo sed -i "s\GRAYLOG_REPORT_RENDER_URI = \"\"\GRAYLOG_REPORT_RENDER_URI = \"http://${GRAYLOG_FQDN}\"\g" ${GRAYLOG_ENV}
    sudo sed -i "s\GRAYLOG_TRANSPORT_EMAIL_WEB_INTERFACE_URL = \"\"\GRAYLOG_TRANSPORT_EMAIL_WEB_INTERFACE_URL = \"https://${GRAYLOG_FQDN}\"\g" ${GRAYLOG_ENV}

    sudo sed -i "s\server_name my.graylog.test;\server_name ${GRAYLOG_FQDN};\g" ${NGINX_HTTP_CONF}

    sudo sed -i "s\hostname: \"samba1\"\hostname: \"${GRAYLOG_FQDN}\"\g" ${GRAYLOG_PATH}/${GRAYLOG_COMPOSE}
    sudo sed -i "s\GF_SERVER_ROOT_URL: \"https://eval.graylog.local/grafana\"\GF_SERVER_ROOT_URL: \"https://${GRAYLOG_FQDN}/grafana\"\g" ${GRAYLOG_PATH}/${GRAYLOG_COMPOSE}

    # Configure Samba to make local Data Adapters accessible from Windows
    echo "[INFO] - CONFIGURE FILESHARES "

    local SHARED_FOLDERS="lookuptables sources"

    for FOLDER in ${SHARED_FOLDERS}
    do
        sudo chmod -R 755 ${GRAYLOG_PATH}/${FOLDER}
        find ${GRAYLOG_PATH}/${FOLDER}/ -type f -print0 | xargs -0 sudo chmod 644 2>/dev/null >/dev/null
    done

    echo "${GRAYLOG_ADMIN}:1000:siem:1000:${GRAYLOG_PASSWORD}" | sudo tee -a "${GRAYLOG_PATH}/samba/users.conf" >/dev/null

    # Installation Cleanup
    sudo rm -rf ${INSTALLPATH}

    # Installation Complete, starting Graylog Stack in Compose
    echo "[INFO] - PREPARATION COMPLETE "
}

function_downloadAdditionalBinaries () {

    local SIDECAR_VERSION="1.5.1"
    local SIDECAR_MSI="https://github.com/Graylog2/collector-sidecar/releases/download/${SIDECAR_VERSION}/graylog-sidecar-${SIDECAR_VERSION}-1.msi"
    local SIDECAR_EXE="https://github.com/Graylog2/collector-sidecar/releases/download/${SIDECAR_VERSION}/graylog_sidecar_installer_${SIDECAR_VERSION}-1.exe"
    local SIDECAR_YML="https://raw.githubusercontent.com/Graylog2/collector-sidecar/refs/heads/master/sidecar-windows-msi-example.yml"
    local FILEBEAT_VERSION="8.19.7"
    local FILEBEAT_ZIP="https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-${FILEBEAT_VERSION}-windows-x86_64.zip"
    local FILEBEAT_MSI="https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-${FILEBEAT_VERSION}-windows-x86_64.msi"
    local MAXMIND_DB_TYPES="ASN City Country"
    
    # Download Maxmind Files (https://github.com/P3TERX/GeoLite.mmdb)
    for DB_TYPE in ${MAXMIND_DB_TYPES}
    do
        echo "[INFO] - DOWNLOAD MAXMIND DATABASE: ${DB_TYPE^^}"
        sudo curl --output-dir ${GRAYLOG_PATH}/maxmind -LOs https://git.io/GeoLite2-${DB_TYPE}.mmdb
        
        # Alternative Source: 
        # https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-${DB_TYPE}.mmdb 
    done

    # Download Graylog Sidecar for Windows
    echo "[INFO] - DOWNLOAD GRAYLOG SIDECAR FOR WINDOWS "
    sudo curl --output-dir ${GRAYLOG_PATH}/sources/binaries/Graylog_Sidecar -LOs ${SIDECAR_MSI}
    sudo curl --output-dir ${GRAYLOG_PATH}/sources/binaries/Graylog_Sidecar -LOs ${SIDECAR_YML}
    sudo curl --output-dir ${GRAYLOG_PATH}/sources/binaries/Graylog_Sidecar -LOs ${SIDECAR_EXE}

    # Download Elastic Filebeat StandaloneSidecar
    echo "[INFO] - DOWNLOAD ELASTIC FILEBEAT STANDALONE FOR WINDOWS "
    sudo curl --output-dir ${GRAYLOG_PATH}/sources/binaries/Filebeat_Standalone -LOs ${FILEBEAT_ZIP}
    sudo curl --output-dir ${GRAYLOG_PATH}/sources/binaries/Filebeat_Standalone -LOs ${FILEBEAT_MSI}
    sudo unzip ${GRAYLOG_PATH}/sources/binaries/Filebeat_Standalone/filebeat-${FILEBEAT_VERSION}-windows-x86_64.zip -d ${GRAYLOG_PATH}/sources/binaries/Filebeat_Standalone/ 2>/dev/null >/dev/null
    sudo cp ${GRAYLOG_PATH}/sources/binaries/Filebeat_Standalone/filebeat-${FILEBEAT_VERSION}-windows-x86_64/filebeat.exe ${GRAYLOG_PATH}/sources/binaries/Filebeat_Standalone/
    sudo rm -rf ${GRAYLOG_PATH}/sources/binaries/Filebeat_Standalone/filebeat-${FILEBEAT_VERSION}-windows-x86_64
    sudo rm ${GRAYLOG_PATH}/sources/binaries/Filebeat_Standalone/filebeat-${FILEBEAT_VERSION}-windows-x86_64.zip

    # Download NXLog - provide a README with instructions on how to do that
    echo "[INFO] - PREPARE (NO DOWNLOAD AVAILABLE) NXLOG AGENT COMMUNITY EDITION FOR WINDOWS "
    sudo touch ${GRAYLOG_PATH}/sources/binaries/NXLog_CommunityEdition/README.txt
    echo "DOWNLOAD LOCATION: https://nxlog.co/downloads/nxlog-ce#nxlog-community-edition" | sudo tee -a ${GRAYLOG_PATH}/sources/binaries/NXLog_CommunityEdition/README.txt 2>/dev/null >/dev/null
    echo "INTEGRATION INSTRUCTIONS: https://docs.nxlog.co/integrate/graylog.html" | sudo tee -a ${GRAYLOG_PATH}/sources/binaries/NXLog_CommunityEdition/README.txt 2>/dev/null >/dev/null
}

function_checkSystemAvailability () {
    while [[ $(curl -s http://localhost/api/system/lbstatus) != "ALIVE" ]]
    do
    echo "[INFO] - WAIT FOR THE SYSTEM TO COME UP "
    sleep 7s
    done

    echo "[INFO] - SYSTEM IS UP NOW"
}

function_createUserToken () {

    # Creating Sidecar Token for Windows Hosts
    USER_ID=$(curl -s http://localhost/api/users -u "${GRAYLOG_ADMIN}":"${GRAYLOG_PASSWORD}" -X GET -H "X-Requested-By: localhost" | jq .[] | jq ".[] | select(.username == \"${1}\")" | jq -r .id)
        
    USER_TOKEN=$(curl -s http://localhost/api/users/${USER_ID}/tokens/evaluation-$1 -u "${GRAYLOG_ADMIN}":"${GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: localhost)" -H 'Content-Type: application/json' -d "{\"token_ttl\":\"P${2}D\"}" | jq -r .token)

    echo ${USER_TOKEN}
}

function_configureBaseFunctionality () {

    echo "[INFO] - PERFORM BASIC CONFIGURATION STEPS "

    # GELF UDP Input for NXLog
    local MONITORING_INPUT=$(curl -s http://localhost/api/system/inputs -u ${GRAYLOG_ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost)" -H 'Content-Type: application/json' -d '{ "global": true, "title": "Port 9900 UDP GELF | Evaluation Input", "type": "org.graylog2.inputs.gelf.udp.GELFUDPInput", "configuration": { "recv_buffer_size": 262144, "port": 9900, "number_worker_threads": 2, "charset_name": "UTF-8", "bind_address": "0.0.0.0" }}'| jq '.id') 

    # Creating FieldType Profile for Docker Logs from Graylog Evaluation Stack
    local MONITORING_FIELD_TYPE_PROFILE=$(curl -s http://localhost/api/system/indices/index_sets/profiles -u ${GRAYLOG_ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{ "custom_field_mappings":[{ "field": "command", "type": "string" }, { "field": "container_name", "type": "string" }, { "field": "image_name", "type": "string" }, { "field": "container_name", "type": "string" }], "name": "Self Monitoring Messages (Evaluation)", "description": "Field Mappings for Self Monitoring Messages" }' | jq '.id')

    # Creating Index for Docker Logs from Graylog Evaluation Stack
    local MONITORING_INDEX=$(curl -s http://localhost/api/system/indices/index_sets -u ${GRAYLOG_ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d "{\"shards\": 1, \"replicas\": 0, \"rotation_strategy_class\": \"org.graylog2.indexer.rotation.strategies.TimeBasedSizeOptimizingStrategy\", \"rotation_strategy\": {\"type\": \"org.graylog2.indexer.rotation.strategies.TimeBasedSizeOptimizingStrategyConfig\", \"index_lifetime_min\": \"P30D\", \"index_lifetime_max\": \"P90D\"}, \"retention_strategy_class\": \"org.graylog2.indexer.retention.strategies.DeletionRetentionStrategy\", \"retention_strategy\": { \"type\": \"org.graylog2.indexer.retention.strategies.DeletionRetentionStrategyConfig\", \"max_number_of_indices\": 20 }, \"data_tiering\": {\"type\": \"hot_only\", \"index_lifetime_min\": \"P30D\", \"index_lifetime_max\": \"P90D\"}, \"title\": \"Self Monitoring Messages (Evaluation)\", \"description\": \"Stores Evaluation System Self Monitoring Messages\", \"index_prefix\": \"gl-self-monitoring\", \"index_analyzer\": \"standard\", \"index_optimization_max_num_segments\": 1, \"index_optimization_disabled\": false, \"field_type_refresh_interval\": 5000, \"field_type_profile\": ${MONITORING_FIELD_TYPE_PROFILE}, \"use_legacy_rotation\": false, \"writable\": true}" | jq '.id')

    # Creating Stream for Docker Logs from Graylog Evaluation Stack
    local MONITORING_STREAM=$(curl -s http://localhost/api/streams -u ${GRAYLOG_ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d "{\"entity\": { \"description\": \"Stream containing all self monitoring events created by Docker\", \"title\": \"System Self Monitoring (Evaluation)\", \"remove_matches_from_default_stream\": true, \"index_set_id\": ${MONITORING_INDEX} }}" | jq -r '.stream_id') 2>/dev/null >/dev/null

    # Creating Stream Rule for Docker Logs from Graylog Evaluation Stack
    curl -s http://localhost/api/streams/${MONITORING_STREAM}/rules -u ${GRAYLOG_ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d "{ \"field\": \"gl2_source_input\", \"description\": \"Self Monitoring Logs\", \"type\": 1, \"inverted\": false, \"value\": ${MONITORING_INPUT} }" 2>/dev/null >/dev/null

    # Start Stream for Docker Logs from Graylog Evaluation Stack
    curl -s http://localhost/api/streams/${MONITORING_STREAM}/resume -u ${GRAYLOG_ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost" 2>/dev/null >/dev/null

    # Activating OTX Lists
    curl -s http://localhost/api/system/content_packs/daf6355e-2d5e-08d3-f9ba-44e84a43df1a/1/installations -u ${GRAYLOG_ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{"entity":{"parameters":{},"comment":"Activated for Evaluation"}}' 2>/dev/null >/dev/null

    # Activating Tor Exit Nodes Lists
    curl -s http://localhost/api/system/content_packs/9350a70a-8453-f516-7041-517b4df0b832/1/installations -u ${GRAYLOG_ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{"entity":{"parameters":{},"comment":"Activated for Evaluation"}}' 2>/dev/null >/dev/null

    # Activating Spamhaus Drop Lists
    curl -s http://localhost/api/system/content_packs/90be5e03-cb16-c802-6462-a244b4a342f3/1/installations -u ${GRAYLOG_ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{"entity":{"parameters":{},"comment":"Activated for Evaluation"}}' 2>/dev/null >/dev/null

    # Activating WHOIS Adapter
    curl -s http://localhost/api/system/content_packs/1794d39d-077f-7360-b92b-95411b05fbce/1/installations -u ${GRAYLOG_ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{"entity":{"parameters":{},"comment":"Activated for Evaluation"}}' 2>/dev/null >/dev/null

    # Activating the GeoIP Resolver Plugin
    curl -s http://localhost/api/system/cluster_config/org.graylog.plugins.map.config.GeoIpResolverConfig -u ${GRAYLOG_ADMIN_TOKEN}:token -X PUT -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{ "enabled":true,"enforce_graylog_schema":true,"db_vendor_type":"MAXMIND","city_db_path":"/etc/graylog/server/mmdb/GeoLite2-City.mmdb","asn_db_path":"/etc/graylog/server/mmdb/GeoLite2-ASN.mmdb","refresh_interval_unit":"DAYS","refresh_interval":14,"use_s3":false }' 2>/dev/null >/dev/null

    # Activating the ThreatIntel Plugin
    curl -s http://localhost/api/system/cluster_config/org.graylog.plugins.threatintel.ThreatIntelPluginConfiguration -u ${GRAYLOG_ADMIN_TOKEN}:token -X PUT -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{"tor_enabled":true,"spamhaus_enabled":true,"abusech_ransom_enabled":false}' 2>/dev/null >/dev/null

    # Disable AWS Instance Lookup and re-order processors (place GeoIP enrichment at the end to ensure custom pipelines get the appropriate value)
    curl -s http://localhost/api/system/messageprocessors/config -u ${GRAYLOG_ADMIN_TOKEN}:token -X PUT -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{"processor_order":[{"name":"AWS Instance Name Lookup","class_name":"org.graylog.aws.processors.instancelookup.AWSInstanceNameLookupProcessor"},{"name":"Illuminate Processor","class_name":"org.graylog.plugins.illuminate.processing.IlluminateMessageProcessor"},{"name":"Message Filter Chain","class_name":"org.graylog2.messageprocessors.MessageFilterChainProcessor"},{"name":"Stream Rule Processor","class_name":"org.graylog2.messageprocessors.StreamMatcherFilterProcessor"},{"name":"Pipeline Processor","class_name":"org.graylog.plugins.pipelineprocessor.processors.PipelineInterpreter"},{"name":"GeoIP Resolver","class_name":"org.graylog.plugins.map.geoip.processor.GeoIpProcessor"}],"disabled_processors":["org.graylog.aws.processors.instancelookup.AWSInstanceNameLookupProcessor"]}' 2>/dev/null >/dev/null

    ## Reconfigure Grafana Credentials
    curl -s http://admin:admin@localhost/grafana/api/users/1 -H 'Content-Type:application/json' -X PUT -d "{ \"name\" : \"Evaluation Admin\", \"login\" : \"${GRAYLOG_ADMIN}\" }" 2>/dev/null > /dev/null 
    curl -s http://${GRAYLOG_ADMIN}:admin@localhost/grafana/api/admin/users/1/password -H 'Content-Type: application/json' -X PUT -d "{ \"password\" : \"$GRAYLOG_PASSWORD\" }" 2>/dev/null > /dev/null 

    ## Configure Prometheus Connector 
    curl -s http://${GRAYLOG_ADMIN}:$GRAYLOG_PASSWORD@localhost/grafana/api/datasources -H 'Content-Type: application/json' -X POST -d '{ "name" : "prometheus", "type" : "prometheus", "url": "http://prometheus1:9090/prometheus", "access": "proxy", "readOnly" : false, "isDefault" : true, "basicAuth" : false }' 2>/dev/null > /dev/null
}

function_displayClusterId () {

    echo ""
    echo "[INFO] - SYSTEM READY FOR TESTING - FOR ADDITIONAL CONFIGURATIONS PLEASE DO REVIEW: ${GRAYLOG_PATH}/graylog.env "
    echo ""
    echo "[INFO] - CLUSTER-ID: $(curl -s localhost/api | jq '.cluster_id' | tr a-z A-Z )" 
    echo ""
    echo "[INFO] - URL: \"http(s)://${GRAYLOG_FQDN}\" "
    echo ""
    echo "[INFO] - CREDENTIALS STORED IN: ${GRAYLOG_PATH}/your_graylog_credentials.txt "    
    echo ""
    echo "[INFO] - USER: \"${GRAYLOG_ADMIN}\" || PASSWORD: \"${GRAYLOG_PASSWORD}\"" | sudo tee ${GRAYLOG_PATH}/your_graylog_credentials.txt 
    echo ""
}

function_checkEnterpriseLicense () {

    while [[ ${GRAYLOG_LICENSE_ENTERPRISE} != "true" ]]
    do 
    echo "[INFO] - WAITING FOR GRAYLOG ENTERPRISE LICENSE TO BE PROVISIONED "
    GRAYLOG_LICENSE_ENTERPRISE=$(curl -H 'Cache-Control: no-cache, no-store' -s http://localhost/api/plugins/org.graylog.plugins.license/licenses/status -u ${GRAYLOG_ADMIN_TOKEN}:token | jq .[] | jq '.[] | select(.active == true and .license.subject == "/license/enterprise")' | jq -r .active )
    sleep 1m
    done
}

function_restartGraylogContainer () {
    local GRAYLOG_CONTAINER=$1
    # Restart Graylog Stack
    echo "[INFO] - RESTART GRAYLOG CONTAINERS FOR MAINTENANCE PURPOSES "
    sudo docker compose -f ${GRAYLOG_PATH}/docker-compose.yaml down ${1} 2>/dev/null >/dev/null
    sudo docker compose -f ${GRAYLOG_PATH}/docker-compose.yaml up -d ${1} --quiet-pull 2>/dev/null >/dev/null
}

function_startGraylogStack () {

    # Start Graylog Stack
    echo "[INFO] - START GRAYLOG STACK - HANG ON, CAN TAKE A WHILE "
    sudo docker compose -f ${GRAYLOG_PATH}/docker-compose.yaml up -d --quiet-pull 2>/dev/null >/dev/null
}

function_stopGraylogStack () {

    # Start Graylog Stack
    echo "[INFO] - STOP GRAYLOG STACK - HANG ON, CAN TAKE A WHILE "
    sudo docker compose -f ${GRAYLOG_PATH}/docker-compose.yaml down 2>/dev/null >/dev/null
}

function_createInputs () {

    # Adding Inputs to make sure Ports map to Nginx configuration
    #
    # Port 514 Syslog UDP Input for Network Devices
    curl -s http://localhost/api/system/inputs  -u ${GRAYLOG_ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost)" -H 'Content-Type: application/json' -d '{ "global": true, "title": "Port 514 UDP Syslog | Evaluation Input", "type": "org.graylog2.inputs.syslog.udp.SyslogUDPInput", "configuration": { "recv_buffer_size": 262144, "port": 514, "number_worker_threads": 2, "charset_name": "UTF-8", "bind_address": "0.0.0.0" }}' 2>/dev/null >/dev/null

    # Port 514 Syslog TCP Input for Network Devices
    curl -s http://localhost/api/system/inputs  -u ${GRAYLOG_ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost)" -H 'Content-Type: application/json' -d '{ "global": true, "title": "Port 514 TCP Syslog | Evaluation Input", "type": "org.graylog2.inputs.syslog.tcp.SyslogTCPInput", "configuration": { "recv_buffer_size": 1048576, "port": 514, "number_worker_threads": 2, "charset_name": "UTF-8", "bind_address": "0.0.0.0" }}' 2>/dev/null >/dev/null

    # Port 5044 Beats Input for Winlogbeat, Auditbeat, Filebeat
    curl -s http://localhost/api/system/inputs  -u ${GRAYLOG_ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost)" -H 'Content-Type: application/json' -d '{ "global": true, "title": "Port 5044 Beats | Evaluation Input", "type": "org.graylog.plugins.beats.Beats2Input", "configuration": { "recv_buffer_size": 1048576, "port": 5044, "number_worker_threads": 2, "charset_name": "UTF-8", "bind_address": "0.0.0.0" }}' 2>/dev/null >/dev/null

    # Port 5045 Beats Input for Winlogbeat, Auditbeat, Filebeat
    curl -s http://localhost/api/system/inputs  -u ${GRAYLOG_ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost)" -H 'Content-Type: application/json' -d '{ "global": true, "title": "Port 5045 Beats | Evaluation Input", "type": "org.graylog.plugins.beats.Beats2Input", "configuration": { "recv_buffer_size": 1048576, "port": 5045, "number_worker_threads": 2, "charset_name": "UTF-8", "bind_address": "0.0.0.0" }}' 2>/dev/null >/dev/null
    
    # Port 5555 RAW TCP Input
    curl -s http://localhost/api/system/inputs  -u ${GRAYLOG_ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost)" -H 'Content-Type: application/json' -d '{ "global": true, "title": "Port 5555 TCP RAW | Evaluation Input", "type": "org.graylog2.inputs.raw.tcp.RawTCPInput", "configuration": { "recv_buffer_size": 1048576, "port": 5555, "number_worker_threads": 2, "charset_name": "UTF-8", "bind_address": "0.0.0.0" }}' 2>/dev/null >/dev/null
        
    # Port 5555 RAW UDP Input
    curl -s http://localhost/api/system/inputs  -u ${GRAYLOG_ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost)" -H 'Content-Type: application/json' -d '{ "global": true, "title": "Port 5555 UDP RAW | Evaluation Input", "type": "org.graylog2.inputs.raw.udp.RawUDPInput", "configuration": { "recv_buffer_size": 262144, "port": 5555, "number_worker_threads": 2, "charset_name": "UTF-8", "bind_address": "0.0.0.0" }}' 2>/dev/null >/dev/null

    # Port 6514 Syslog TCP over TLS Input for Network Devices
    curl -s http://localhost/api/system/inputs  -u ${GRAYLOG_ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost)" -H 'Content-Type: application/json' -d '{ "global": true, "title": "Port 6514 TCP Syslog over TLS | Evaluation Input", "type": "org.graylog2.inputs.syslog.tcp.SyslogTCPInput", "configuration": { "recv_buffer_size": 1048576, "port": 6514, "number_worker_threads": 2, "charset_name": "UTF-8", "bind_address": "0.0.0.0", "tls_cert_file": "/etc/graylog/server/input_tls/cert.crt", "tls_key_file": "/etc/graylog/server/input_tls/tls.key", "tls_enable": true, "tls_key_password": "test123" }}' 2>/dev/null >/dev/null

    # Port 12201 GELF TCP Input for NXLog
    curl -s http://localhost/api/system/inputs  -u ${GRAYLOG_ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost)" -H 'Content-Type: application/json' -d '{ "global": true, "title": "Port 12201 TCP GELF | Evaluation Input", "type": "org.graylog2.inputs.gelf.tcp.GELFTCPInput", "configuration": { "recv_buffer_size": 1048576, "port": 12201, "number_worker_threads": 2, "charset_name": "UTF-8", "bind_address": "0.0.0.0" }}' 2>/dev/null >/dev/null

    # Port 12201 GELF UDP Input for NXLog
    curl -s http://localhost/api/system/inputs  -u ${GRAYLOG_ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost)" -H 'Content-Type: application/json' -d '{ "global": true, "title": "Port 12201 UDP GELF | Evaluation Input", "type": "org.graylog2.inputs.gelf.udp.GELFUDPInput", "configuration": { "recv_buffer_size": 262144, "port": 12201, "number_worker_threads": 2, "charset_name": "UTF-8", "bind_address": "0.0.0.0" }}' 2>/dev/null >/dev/null

    # Stopping all Inputs to allow a controlled Log Source Onboarding
    echo "[INFO] - STOPPING ALL INPUTS" 
    for INPUT in $(curl -s http://localhost/api/cluster/inputstates  -u ${GRAYLOG_ADMIN_TOKEN}:token -X GET | jq -r '.[] | map(.) | .[].id'); do
        curl -s http://localhost/api/cluster/inputstates/${INPUT}  -u ${GRAYLOG_ADMIN_TOKEN}:token -X DELETE -H "X-Requested-By: localhost" -H 'Content-Type: application/json' 2>/dev/null >/dev/null
    done
}

###############################################################################
#
# Graylog Installation

if [[ $(cat ${GRAYLOG_PATH}/.installation 2>/dev/null >/dev/null) == "started" ]]
then
    echo "[INFO] - INSTALLATION WAS INTERRUPTED, RESET TO SNAPSHOT" 
    exit
elif [[ $(cat ${GRAYLOG_PATH}/.installation 2>/dev/null >/dev/null) == "" ]]
then
    sudo mkdir -p ${GRAYLOG_PATH}
    echo "started" | sudo tee ${GRAYLOG_PATH}/.installation 2>/dev/null >/dev/null

    function_checkSnapshot

    function_defineAdminName
    function_defineAdminPassword

    function_getSystemFqdn

    function_checkSystemRequirements

    function_installScriptDependencies
    function_installDocker

    function_installGraylogStack

    function_startGraylogStack

    function_downloadAdditionalBinaries

    function_checkSystemAvailability

    GRAYLOG_ADMIN_TOKEN=$(function_createUserToken $GRAYLOG_ADMIN 14)
    GRAYLOG_SIDECAR_TOKEN=$(function_createUserToken $GRAYLOG_SIDECAR 730)

    function_configureBaseFunctionality
 
    function_restartGraylogContainer graylog1

    function_displayClusterId
    
    echo "*/5 * * * * root /bin/bash $(pwd)/install-graylog.sh ${GRAYLOG_ADMIN_TOKEN}" | sudo tee ${SYSTEM_CRONPATH} 2>/dev/null >/dev/null
    echo "completed" | sudo tee ${GRAYLOG_PATH}/.installation 2>/dev/null >/dev/null

    exit
fi


###############################################################################
#
# Post-Installation Tasks

if [[ $(cat ${GRAYLOG_PATH}/.installation 2>/dev/null >/dev/null) == "completed" ]]
then
    echo "continued" | sudo tee ${GRAYLOG_PATH}/.installation 2>/dev/null >/dev/null

    function_checkEnterpriseLicense
    function_stopGraylogStack
    function_startGraylogStack
    function_checkSystemAvailability
    function_createInputs
fi

#sudo rm $0

exit