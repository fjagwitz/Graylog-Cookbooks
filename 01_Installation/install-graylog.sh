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
GRAYLOG_FQDN=""

INSTALL_LOG="./graylog-eval-installation.log"
SCRIPT_DEPENDENCIES="dnsutils net-tools vim git jq tcpdump pwgen acl htop unzip curl ca-certificates" 
SYSTEM_PROXY=$(cat /etc/environment | grep http_proxy | cut -d "=" -f 2 | tr -d '"')



###############################################################################
#
# Functions Definition

function_checkSnapshot () {

    read -p "[INPUT] - Please confirm that you created a Snapshot of this VM before running this Script [yes/no]: " SNAPSHOT_CREATED

    local SNAPSHOT_CREATED=${SNAPSHOT_CREATED:-no}

    if [[ ${SNAPSHOT_CREATED} != "yes" ]]
    then
        echo "[ERROR] - No snapshot was created, please create one - exiting" 
        exit
    fi 
}

function_defineAdminName () {

    while [[ ${VALID_ADMIN} != "true" ]]
    do
        read -p "[INPUT] - Please add the name of your central Administration User [admin]: " GRAYLOG_ADMIN
        
        local ADMIN_NAME=${ADMIN_NAME:-admin}
        local FORBIDDEN_USERNAMES=$(cat /etc/passwd | awk -F":" '{print $1}')
        
        if [[ ${ADMIN_NAME} =~ ^[A-Za-z0-9_-]{4,12}$ ]]
        then
            for USER_NAME in ${FORBIDDEN_USERNAMES}
            do
                if [[ ${ADMIN_NAME} == ${USER_NAME} ]]
                then                    
                    echo "[INFO] - A valid Username MUST NOT be available on this system, try again" 
                    VALID_ADMIN="false"
                    break
                else
                    VALID_ADMIN="true"

                    # Set global Variable for Graylog Admin
                    GRAYLOG_ADMIN=${ADMIN_NAME}
                fi
            done
        else
            echo "[INFO] - A valid Username consists of 4-12 letters, try again" 
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
                echo "[WARN] - Continue without validated FQDN, expecting Product issues " 
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

    if [ ${OPERATING_SYSTEM,,} == "ubuntu" ] && [ ${RANDOM_ACCESS_MEMORY} -ge 32 ] && [ ${CPU_CORES_NUMBER} -ge 8 ] && [ ${CPU_REQUIRED_FLAGS,,} == "avx" ] && [ ${INTERNET_CONNECTIVITY} -eq 200 ]
    then
        echo "[INFO] - System Requirements Check successful: 

                Operating System: ${OPERATING_SYSTEM}
                Memory          : ${RANDOM_ACCESS_MEMORY} GB
                CPU Cores       : ${CPU_CORES_NUMBER} vCPU
                CPU Flags       : ${CPU_REQUIRED_FLAGS^^} available (for running MongoDB)
                Internet        : Available
                "
    else
        if [ ${INTERNET_CONNECTIVITY} -ne 200 ]
        then
            echo "[ERROR] - Internet is not available from this machine "
        fi
        if [ ${OPERATING_SYSTEM,,} != "ubuntu" ]
        then
            echo "[ERROR] - Operating System MUST be Ubuntu, but is ${OPERATING_SYSTEM}" 
        fi
        if [ ${RANDOM_ACCESS_MEMORY} -lt 32 ]
        then
            echo "[ERROR] - Memory must be at least 32 GB, but is only ${RANDOM_ACCESS_MEMORY} GB" 
        fi
        if [ ${CPU_CORES_NUMBER} -lt 8 ]
        then
            echo "[ERROR] - The System must have at least 8 vCPU Cores, but has only ${CPU_CORES_NUMBER}" 
        fi
        if [ ${CPU_REQUIRED_FLAGS^^} != "AVX" ]
        then
            echo "[ERROR] - The CPU must support the AVX Flag for running MongoDB, but does not" 
        fi
        exit
    fi
}

function_installScriptDependencies () {

    echo "[INFO] - PERFORMING SYSTEM UPDATE "   
    sudo apt -qq update -y 2>/dev/null >/dev/null 
    sudo apt -qq upgrade -y 2>/dev/null >/dev/null
    echo "[INFO] - PERFORMING SYSTEM CLEANUP "  
    sudo apt -qq autoremove -y 2>/dev/null >/dev/null
    echo "[INFO] - Installing required packages: ${SCRIPT_DEPENDENCIES} " 
    sudo apt -qq install -y ${SCRIPT_DEPENDENCIES} 2>/dev/null >/dev/null
}

function_installDocker () {

    echo "[INFO] - Installing Docker CE " 

    local DOCKER_OS_PACKAGES="docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc"
    local DOCKER_CE_PACKAGES="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
    local DOCKER_URL="https://download.docker.com/linux/ubuntu"
    local DOCKER_KEY="/etc/apt/keyrings/docker.asc"

    if [ "$(docker -v | cut -d " " -f1 )" == "Docker" ] 
    then
        echo "[INFO] - DOCKER INSTALLED, CONTINUE "
    else
        echo "[INFO] - DOCKER WILL BE INSTALLED NOW "
        # Removing preconfigured Docker Installation from Ubuntu (just in case)
        echo "[INFO] - DOCKER CLEANUP "
        for PKG in ${DOCKER_PACKAGES} 
        do 
            sudo apt-get -qq remove $PKG 2>/dev/null >/dev/null
        done

        # Adding Docker Repository
        echo "[INFO] - ADDING DOCKER REPOSITORY "
        sudo install -m 0755 -d /etc/apt/keyrings > /dev/null
        sudo curl -fsSL ${DOCKER_URL}/gpg -o ${DOCKER_KEY} > /dev/null
        sudo chmod a+r ${DOCKER_KEY}

        echo   "deb [arch=$(dpkg --print-architecture) signed-by=${DOCKER_KEY}] ${DOCKER_URL}   $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get -qq update 2>/dev/null >/dev/null

        # Installing Docker on Ubuntu
        echo "[INFO] - DOCKER INSTALLATION "
        sudo apt -qq install -y ${DOCKER_CE_PACKAGES} 2>/dev/null >/dev/null

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
    local GRAYLOG_ENV="/opt/graylog/graylog.env"
    local DATABASE_ENV="/opt/graylog/database.env"

    # Configure vm.max_map_count for Opensearch (https://opensearch.org/docs/2.15/install-and-configure/install-opensearch/index/#important-settings)
    echo "[INFO] - SET OPENSEARCH SETTINGS "
    echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf > /dev/null
    sudo sysctl -p > /dev/null

    sudo mkdir -p ${INSTALLPATH}

    # Create required Folders in the Filesystem
    echo "[INFO] - CREATE FOLDERS "
    sudo mkdir -p ${GRAYLOG_PATH}/{archives,configuration,contentpacks,database/{datanode1,datanode2,datanode3,warm_tier},datalake,lookuptables,maxmind,nginx1,nginx2,notifications,prometheus,shared/{assetdata,input_tls,logsamples,lookuptables,rootcerts},sources/{scripts,binaries/{Graylog_Sidecar,Filebeat_Standalone,NXLog_CommunityEdition},other}}

    echo "[INFO] - CLONE GIT REPO "
    sudo git clone -q --single-branch --branch Graylog-${GRAYLOG_VERSION} https://github.com/fjagwitz/Graylog-Cookbooks.git ${INSTALLPATH}

    echo "[INFO] - POPULATE FOLDERS FROM GIT REPO CONTENT "
    local ITEMS=$(ls ${INSTALLPATH}/01_Installation/compose | xargs)

    for ITEM in ${ITEMS}
    do
        cp -R ${INSTALLPATH}/01_Installation/compose/${ITEM} ${GRAYLOG_PATH}
    done

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

    sudo sed -i "s\GF_SERVER_ROOT_URL: \"https://eval.graylog.local/grafana\"\GF_SERVER_ROOT_URL: \"https://${GRAYLOG_FQDN}/grafana\"\g" ${GRAYLOG_PATH}/${GRAYLOG_COMPOSE}

    # Configure Samba to make local Data Adapters accessible from Windows
    #echo "[INFO] - CONFIGURE FILESHARES "
    #sudo chmod 755 ${GRAYLOG_PATH}/lookuptables/* ${GRAYLOG_PATH}/sources/*
    #sudo adduser ${GL_GRAYLOG_ADMIN} --system < /dev/null > /dev/null
    #sudo setfacl -Rm u:${GL_GRAYLOG_ADMIN}:rwx,d:u:${GL_GRAYLOG_ADMIN}:rwx ${GL_GRAYLOG_ASSETDATA} ${GL_GRAYLOG_LOOKUPTABLES} ${GL_GRAYLOG_SOURCES}
    #sudo mv /etc/samba/smb.conf /etc/samba/smb.conf.bak
    #sudo mv ${installpath}/01_Installation/compose/samba/smb.conf /etc/samba/smb.conf
    #echo -e "${GL_GRAYLOG_PASSWORD}\n${GL_GRAYLOG_PASSWORD}" | sudo smbpasswd -a -s ${GL_GRAYLOG_ADMIN} > /dev/null
    #sudo sed -i -e "s/valid users = GLADMIN/valid users = ${GL_GRAYLOG_ADMIN}/g" /etc/samba/smb.conf 
    #sudo service smbd restart


    # Installation Cleanup
    sudo rm -rf ${INSTALLPATH}

    # Installation Complete, starting Graylog Stack in Compose
    echo "[INFO] - PREPARATION COMPLETE, CONTINUE "

}

function_downloadAdditionalBinaries () {

    local SIDECAR_MSI="https://github.com/Graylog2/collector-sidecar/releases/download/1.5.1/graylog-sidecar-1.5.1-1.msi"
    local SIDECAR_EXE="https://github.com/Graylog2/collector-sidecar/releases/download/1.5.1/graylog_sidecar_installer_1.5.1-1.exe"
    local SIDECAR_YML="https://raw.githubusercontent.com/Graylog2/collector-sidecar/refs/heads/master/sidecar-windows-msi-example.yml"
    local FILEBEAT_ZIP="https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-8.19.3-windows-x86_64.zip"

    # Download Maxmind Files (https://github.com/P3TERX/GeoLite.mmdb)
    echo "[INFO] - DOWNLOAD MAXMIND DATABASES "
    sudo curl --output-dir ${GRAYLOG_PATH}/maxmind -LOs https://git.io/GeoLite2-ASN.mmdb
    # OR use https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-ASN.mmdb 
    sudo curl --output-dir ${GRAYLOG_PATH}/maxmind -LOs https://git.io/GeoLite2-City.mmdb
    # OR use https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb 
    sudo curl --output-dir ${GRAYLOG_PATH}/maxmind -LOs https://git.io/GeoLite2-Country.mmdb
    # OR use https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb

    # Download Graylog Sidecar for Windows
    echo "[INFO] - DOWNLOAD GRAYLOG SIDECAR FOR WINDOWS "
    sudo curl --output-dir ${GRAYLOG_PATH}/sources/binaries/Graylog_Sidecar -LOs ${SIDECAR_MSI}
    sudo curl --output-dir ${GRAYLOG_PATH}/sources/binaries/Graylog_Sidecar -LOs ${SIDECAR_YML}
    sudo curl --output-dir ${GRAYLOG_PATH}/sources/binaries/Graylog_Sidecar -LOs ${SIDECAR_EXE}

    # Download Elastic Filebeat StandaloneSidecar
    echo "[INFO] - DOWNLOAD ELASTIC FILEBEAT STANDALONE FOR WINDOWS "
    sudo curl --output-dir ${GRAYLOG_PATH}/sources/binaries/Filebeat_Standalone -LOs ${FILEBEAT_ZIP}
    sudo unzip ${GRAYLOG_PATH}/sources/binaries/Filebeat_Standalone/filebeat-8.19.3-windows-x86_64.zip -d ${GRAYLOG_PATH}/sources/binaries/Filebeat_Standalone/ 2>/dev/null >/dev/null
    sudo cp ${GRAYLOG_PATH}/sources/binaries/Filebeat_Standalone/filebeat-8.19.3-windows-x86_64/filebeat.exe ${GRAYLOG_PATH}/sources/binaries/Filebeat_Standalone/
    sudo rm -rf ${GRAYLOG_PATH}/sources/binaries/Filebeat_Standalone/filebeat-8.19.3-windows-x86_64
    sudo rm ${GRAYLOG_PATH}/sources/binaries/Filebeat_Standalone/filebeat-8.19.3-windows-x86_64.zip

    # Download NXLog - provide a README with instructions on how to do that
    echo "[INFO] - DOWNLOAD NXLOG AGENT COMMUNITY EDITION FOR WINDOWS (PREPARATORY STEP) "
    sudo touch ${GRAYLOG_PATH}/sources/binaries/NXLog_CommunityEdition/README.txt
    echo "DOWNLOAD LOCATION: https://nxlog.co/downloads/nxlog-ce#nxlog-community-edition" | sudo tee -a ${GRAYLOG_PATH}/sources/binaries/NXLog_CommunityEdition/README.txt 2>/dev/null >/dev/null
    echo "INTEGRATION INSTRUCTIONS: https://docs.nxlog.co/integrate/graylog.html" | sudo tee -a ${GRAYLOG_PATH}/sources/binaries/NXLog_CommunityEdition/README.txt 2>/dev/null >/dev/null
}

###############################################################################
#
# Graylog Installation

function_checkSnapshot

function_defineAdminName
function_defineAdminPassword

function_getSystemFqdn

function_checkSystemRequirements

function_installScriptDependencies
function_installDocker

function_installGraylogStack

function_downloadAdditionalBinaries