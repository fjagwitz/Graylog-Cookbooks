#!/bin/bash
#
# title:             GRAYLOG-INSTALLER
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
GRAYLOG_ADMIN_TOKEN="$(cat ${GRAYLOG_PATH}/.admintoken 2>/dev/null)"
GRAYLOG_FQDN=$(nslookup 172.16.199.182 | grep in-addr.arpa | grep -v NXDOMAIN | cut -d "=" -f2 | tr -d " ")
GRAYLOG_SIDECAR="graylog-sidecar"
GRAYLOG_LICENSE_ENTERPRISE=""
GRAYLOG_LICENSE_SECURITY=""

SYSTEM_PROXY=$(cat /etc/environment | grep -iw http_proxy | cut -d "=" -f 2 | tr -d '"')

# Define minimum system requirements
SYSTEM_REQUIREMENTS_CPU="8"
SYSTEM_REQUIREMENTS_CPU_FLAGS="avx"
SYSTEM_REQUIREMENTS_MEMORY="32"
SYSTEM_REQUIREMENTS_DISK="600"
SYSTEM_REQUIREMENTS_OS="Ubuntu"

# Define required dependencies to run the script as well as the Graylog Stack
SCRIPT_DEPENDENCIES="ca-certificates curl cron dnsutils dos2unix git htop iproute2 jq net-tools pwgen rsyslog tcpdump unzip vim" 


###############################################################################
#
# Functions Definition

function_checkSnapshot () {

    read -p "[INPUT] - Please confirm that you created a Snapshot of the VM before running this Script [no/yes]: " SNAPSHOT_CREATED

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
        read -p "[INPUT] - Please add the fqdn of your Graylog Instance [${GRAYLOG_FQDN}]: " SYSTEM_FQDN
        local SYSTEM_FQDN=${SYSTEM_FQDN:-${GRAYLOG_FQDN}}
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
            read -p "[INPUT] - The FQDN you provided does not seem to be resolvable; continue anyway? [no/yes]: " CHECK_IGNORE
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

function_checkInternetConnectivity () {
    local INTERNET_CONNECTIVITY=$(curl -ILs https://github.com --connect-timeout 7 | head -n1 | cut -d " " -f2)
    if [ $INTERNET_CONNECTIVITY != 200 ]
    then
        echo "[INFO] - INTERNET CONNECTION NOT AVAILABLE. EXIT."
        exit
    else
        echo "[INFO] - INTERNET CONNECTION SUCCESSFULLY ESTABLISHED " | logger -p user.info -e -t GRAYLOG-INSTALLER
    fi
}

function_checkSystemRequirements () {

    local INTERNET_CONNECTIVITY=$(curl -ILs https://github.com --connect-timeout 7 | head -n1 | cut -d " " -f2)
    local OPERATING_SYSTEM=$(hostnamectl | grep -i "operating system" | cut -d " " -f3)
    local RANDOM_ACCESS_MEMORY=$(vmstat -s | grep "total memory" | grep -o [0-9]* | awk '{print int($0/1024/1024)+1}')
    local CPU_CORES_NUMBER=$(nproc)
    local CPU_REQUIRED_FLAGS=$(lscpu | grep -wio avx)
    local TOTAL_DISK_SPACE=$(df -hP /opt | awk '{print $2}' | tail -n1 | grep -oE [0-9]*)

    if [[ "${SYSTEM_PROXY}" == "" ]]
    then
        local INTERNET_CONNECTIVITY_TYPE="direct (without Proxy)"
    else
        local INTERNET_CONNECTIVITY_TYPE="proxied: "
    fi 

    if [ ${OPERATING_SYSTEM,,} == ${SYSTEM_REQUIREMENTS_OS,,} ] && [ ${RANDOM_ACCESS_MEMORY} -ge ${SYSTEM_REQUIREMENTS_MEMORY} ] && [ ${CPU_CORES_NUMBER} -ge ${SYSTEM_REQUIREMENTS_CPU} ] && [[ ${CPU_REQUIRED_FLAGS,,} == ${SYSTEM_REQUIREMENTS_CPU_FLAGS,,} ]] && [ ${TOTAL_DISK_SPACE} -ge ${SYSTEM_REQUIREMENTS_DISK} ] && [ ${INTERNET_CONNECTIVITY} -eq 200 ]
    then
        echo "[INFO] - SYSTEM REQUIREMENTS CHECK SUCCESSFUL: 
        
         Operating System: ${OPERATING_SYSTEM} 
         Storage         : ${TOTAL_DISK_SPACE} GB 
         Memory          : ${RANDOM_ACCESS_MEMORY} GB 
         CPU Cores       : ${CPU_CORES_NUMBER} vCPU 
         CPU Flags       : ${CPU_REQUIRED_FLAGS^^} available 
         Internet        : ${INTERNET_CONNECTIVITY_TYPE^}${SYSTEM_PROXY}
        "
    else
        if [ ${INTERNET_CONNECTIVITY} -ne 200 ]
        then
            echo "[ERROR] - INTERNET IS NOT AVAILABLE FROM THIS MACHINE "
        fi
        if [ ${OPERATING_SYSTEM,,} != ${SYSTEM_REQUIREMENTS_OS,,} ]
        then
            echo "[ERROR] - OPERATING SYSTEM MUST BE UBUNTU, BUT IS ${OPERATING_SYSTEM}" 
        fi
        if [ ${RANDOM_ACCESS_MEMORY} -lt ${SYSTEM_REQUIREMENTS_MEMORY} ]
        then
            echo "[ERROR] - MEMORY MUST BE AT LEAST ${SYSTEM_REQUIREMENTS_MEMORY} GB, BUT IS ONLY ${RANDOM_ACCESS_MEMORY} GB" 
        fi
        if [ ${CPU_CORES_NUMBER} -lt ${SYSTEM_REQUIREMENTS_CPU} ]
        then
            echo "[ERROR] - THE SYSTEM MUST HAVE AT LEAST ${SYSTEM_REQUIREMENTS_CPU} VCPU CORES, BUT HAS ONLY ${CPU_CORES_NUMBER}" 
        fi
        if [[ ${CPU_REQUIRED_FLAGS,,} != ${SYSTEM_REQUIREMENTS_CPU_FLAGS,,} ]]
        then
            echo "[ERROR] - THE CPU MUST SUPPORT THE ${SYSTEM_REQUIREMENTS_CPU_FLAGS^^} FLAG(S), BUT DOES NOT" 
        fi
        if [ ${TOTAL_DISK_SPACE} -lt ${SYSTEM_REQUIREMENTS_DISK} ]
        then
            echo "[ERROR] - THE /opt FOLDER MUST PROVIDE AT LEAST ${SYSTEM_REQUIREMENTS_DISK} GB STORAGE, BUT HAS ONLY ${TOTAL_DISK_SPACE} GB"
        fi
        exit
    fi

}

function_installScriptDependencies () {

    echo "[INFO] - VALIDATE SCRIPT DEPENDENCIES" | logger -p user.info -e -t GRAYLOG-INSTALLER
    sudo apt -qq update -y 2>/dev/null >/dev/null
    # sudo apt -qq upgrade -y 2>/dev/null > /dev/null
    sudo apt -qq autoremove -y 2>/dev/null >/dev/null

    for DEP in ${SCRIPT_DEPENDENCIES}
    do 
        if [[ ${DEP} != $(dpkg -l | grep -E "(^| )${DEP}($| )" | cut -d" " -f3) ]]
        then
            echo "[INFO] - INSTALL SCRIPT DEPENDENCY: ${DEP^^} " | logger -p user.info -e -t GRAYLOG-INSTALLER
            sudo apt -qq install -y ${DEP} 2>/dev/null >/dev/null
            wait
        fi
    done

    echo "[INFO] - ADD ${USER^^} TO TCPDUMP GROUP" | logger -p user.info -e -t GRAYLOG-INSTALLER
    sudo usermod -aG tcpdump ${USER} 2>/dev/null >/dev/null

}

# following https://docs.docker.com/engine/install/ubuntu
function_installDocker () {

    local DOCKER_OS_PACKAGES="docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc"
    local DOCKER_CE_PACKAGES="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
    local DOCKER_URL="https://download.docker.com/linux/ubuntu"
    local DOCKER_KEY="/etc/apt/keyrings/docker.asc"
    local DOCKER_GROUP="docker"
    local DOCKER_INSTALLED=$(command -v docker)

    if [[ ${DOCKER_INSTALLED} == "" ]]
    then

        echo "[INFO] - REMOVE DOCKER LEFTOVERS" | logger -p user.info -e -t GRAYLOG-INSTALLER
    
        sudo apt -qq remove ${DOCKER_OS_PACKAGES} 2>/dev/null >/dev/null
        
        echo "[INFO] - ADD DOCKER REPOSITORY" | logger -p user.info -e -t GRAYLOG-INSTALLER

        sudo install -m 0755 -d /etc/apt/keyrings 2>/dev/null >/dev/null 
        sudo curl -fsSL ${DOCKER_URL}/gpg -o ${DOCKER_KEY} 2>/dev/null >/dev/null 
        sudo chmod a+r ${DOCKER_KEY} 2>/dev/null >/dev/null 
        echo "deb [arch=$(dpkg --print-architecture) signed-by=${DOCKER_KEY}] ${DOCKER_URL}   $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list 2>/dev/null >/dev/null 
        sudo apt -qq update 2>/dev/null >/dev/null

        for PKG in ${DOCKER_CE_PACKAGES}
        do 
            echo "[INFO] - INSTALL DOCKER PACKAGE: ${PKG^^} " | logger -p user.info -e -t GRAYLOG-INSTALLER
            sudo apt -qq install -y ${PKG} 2>/dev/null >/dev/null
            wait
        done
    fi

    echo "[INFO] - ADD ${USER^^} TO DOCKER GROUP" | logger -p user.info -e -t GRAYLOG-INSTALLER
    sudo usermod -aG docker ${USER} 2>/dev/null >/dev/null

    echo "[INFO] - RESTART DOCKER SERVICE" | logger -p user.info -e -t GRAYLOG-INSTALLER
    sudo systemctl docker.service restart 2>/dev/null >/dev/null

}

# following https://go2docs.graylog.org/current/getting_in_log_data/set_up_sidecar_collectors.htm
function_installGraylogSidecar () {
    
    local SIDECAR_INSTALLED=$(dpkg -l | grep -E "(^| )graylog-sidecar($| )" | cut -d" " -f3)
    local SIDECAR_YAML="/etc/graylog/sidecar/sidecar.yml"
    local SIDECAR_TOKEN="${1}"

    if [[ ${SIDECAR_INSTALLED} != "graylog-sidecar" ]]
    then

        echo "[INFO] - ADD GRAYLOG SIDECAR REPOSITORY" | logger -p user.info -e -t GRAYLOG-INSTALLER
        sudo wget https://packages.graylog2.org/repo/packages/graylog-sidecar-repository_1-5_all.deb 2>/dev/null >/dev/null
        sudo dpkg -i graylog-sidecar-repository_1-5_all.deb 2>/dev/null >/dev/null

        echo "[INFO] - INSTALL GRAYLOG SIDECAR " | logger -p user.info -e -t GRAYLOG-INSTALLER
        sudo apt -qq update -y 2>/dev/null >/dev/null
        sudo apt -qq install -y graylog-sidecar 2>/dev/null >/dev/null
        sudo rm graylog-sidecar-repository_1-5_all.deb 2>/dev/null >/dev/null

        echo "[INFO] - CONFIGURE GRAYLOG SIDECAR ON HOST" | logger -p user.info -e -t GRAYLOG-INSTALLER
        sudo cp ${SIDECAR_YAML} ${SIDECAR_YAML}.bak
        sudo sed -i "s\#server_url: \"http://127.0.0.1:9000/api/\"\server_url: \"http://localhost/api/\"\g" ${SIDECAR_YAML}
        sudo sed -i "s\server_api_token: \"\"\server_api_token: \"${SIDECAR_TOKEN}\"\g" ${SIDECAR_YAML}
        sudo sed -i 's/  - default/  - self-beats/g' ${SIDECAR_YAML}
    fi
}

function_installGraylogStack () {

    local INSTALLPATH="/tmp/graylog"
    local FOLDERS_WITH_GRAYLOG_PERMISSIONS="archives datalake input_tls journal1 journal2 notifications"
    local GRAYLOG_ENV="${GRAYLOG_PATH}/${GRAYLOG_SERVER_ENV}"
    local DATABASE_ENV="${GRAYLOG_PATH}/${GRAYLOG_DATABASE_ENV}"
    local NGINX_HTTP_CONF="${GRAYLOG_PATH}/nginx1/http.conf"

    # Configure vm.max_map_count for Opensearch (https://docs.opensearch.org/2.19/install-and-configure/install-opensearch/index)
    echo "[INFO] - CONFIGURE FILESYSTEM FOR OPENSEARCH " | logger -p user.info -e -t GRAYLOG-INSTALLER   
    echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf >/dev/null 
    sudo sysctl -p >/dev/null 

    sudo mkdir -p ${INSTALLPATH}

    # Create required Folders in the Filesystem
    echo "[INFO] - CREATE REQUIRED SUBFOLDERS IN /OPT " | logger -p user.info -e -t GRAYLOG-INSTALLER
    sudo mkdir -p ${GRAYLOG_PATH}/{archives,assetdata,configuration,contentpacks,database/{datanode1,datanode2,datanode3,warm_tier},datalake,input_tls,journal1,journal2,logsamples,lookuptables,maxmind,nginx1,nginx2,notifications,prometheus,rootcerts,samba,sources/{scripts,binaries/{Graylog_Sidecar/{MSI,EXE},Filebeat_Standalone,NXLog_CommunityEdition},other}}

    echo "[INFO] - CLONE GITHUB REPO " | logger -p user.info -e -t GRAYLOG-INSTALLER
    sudo git clone -q --single-branch --branch Graylog-${GRAYLOG_VERSION} https://github.com/fjagwitz/Graylog-Cookbooks.git ${INSTALLPATH} 

    echo "[INFO] - COPY CLONED CONTENT TO FOLDERS " | logger -p user.info -e -t GRAYLOG-INSTALLER
    local ITEMS=$(ls ${INSTALLPATH}/01_Installation/compose | xargs)

    for ITEM in ${ITEMS}
    do
        sudo cp -R ${INSTALLPATH}/01_Installation/compose/${ITEM} ${GRAYLOG_PATH}
    done
    
    # Start pulling Containers
    echo "[INFO] - PULL CONTAINERS FOR GRAYLOG STACK " | logger -p user.info -e -t GRAYLOG-INSTALLER
    sudo docker compose -f ${GRAYLOG_PATH}/docker-compose.yaml pull --quiet 2>/dev/null >/dev/null &

    echo "[INFO] - SET PERMISSIONS FOR UID/GID 1000 (OPENSEARCH)" | logger -p user.info -e -t GRAYLOG-INSTALLER
    # Adapting Permissions for proper access by the Opensearch Containers (1000:1000)
    sudo chown -R 1000:1000 ${GRAYLOG_PATH}/database

    echo "[INFO] - SET PERMISSIONS FOR UID/GID 1100 (GRAYLOG) " | logger -p user.info -e -t GRAYLOG-INSTALLER
    # Adapting Permissions for proper access by the Graylog Containers (1100:1100)
    for FOLDER in ${FOLDERS_WITH_GRAYLOG_PERMISSIONS}
    do
        sudo chown -R 1100:1100 ${GRAYLOG_PATH}/${FOLDER}
    done
    
    echo "[INFO] - RENAME GRAYLOG ENVIRONMENT FILE " | logger -p user.info -e -t GRAYLOG-INSTALLER
    sudo mv ${GRAYLOG_PATH}/graylog.example ${GRAYLOG_PATH}/graylog.env

    echo "[INFO] - POPULATE ENVIRONMENT FILE FOR OPENSEARCH " | logger -p user.info -e -t GRAYLOG-INSTALLER
    echo "OPENSEARCH_INITIAL_ADMIN_PASSWORD = \"$(pwgen -N 1 -s 48)\"" | sudo tee -a ${DATABASE_ENV} >/dev/null 
    echo "OPENSEARCH_JAVA_OPTS = \"-Xms4096m -Xmx4096m\"" | sudo tee -a ${DATABASE_ENV} >/dev/null 

    echo "[INFO] - POPULATE ENVIRONMENT FILE FOR GRAYLOG " | logger -p user.info -e -t GRAYLOG-INSTALLER
    local SYSTEM_PASSWORD_SECRET=$(pwgen -N 1 -s 96)
    local SYSTEM_ROOT_PASSWORD_SHA2=$(echo ${GRAYLOG_PASSWORD} | head -c -1 | shasum -a 256 | cut -d" " -f1)

    sudo sed -i "s\GRAYLOG_ROOT_USERNAME = \"\"\GRAYLOG_ROOT_USERNAME = \"${GRAYLOG_ADMIN}\"\g" ${GRAYLOG_ENV}
    sudo sed -i "s\GRAYLOG_ROOT_PASSWORD_SHA2 = \"\"\GRAYLOG_ROOT_PASSWORD_SHA2 = \"${SYSTEM_ROOT_PASSWORD_SHA2}\"\g" ${GRAYLOG_ENV}
    sudo sed -i "s\GRAYLOG_PASSWORD_SECRET = \"\"\GRAYLOG_PASSWORD_SECRET = \"${SYSTEM_PASSWORD_SECRET}\"\g" ${GRAYLOG_ENV}
    sudo sed -i "s\GRAYLOG_HTTP_EXTERNAL_URI = \"\"\GRAYLOG_HTTP_EXTERNAL_URI = \"https://${GRAYLOG_FQDN}/\"\g" ${GRAYLOG_ENV}
    sudo sed -i "s\GRAYLOG_REPORT_RENDER_URI = \"\"\GRAYLOG_REPORT_RENDER_URI = \"http://${GRAYLOG_FQDN}\"\g" ${GRAYLOG_ENV}
    sudo sed -i "s\GRAYLOG_TRANSPORT_EMAIL_WEB_INTERFACE_URL = \"\"\GRAYLOG_TRANSPORT_EMAIL_WEB_INTERFACE_URL = \"https://${GRAYLOG_FQDN}\"\g" ${GRAYLOG_ENV}

    if [ "${SYSTEM_PROXY}" != "" ]
    then
        sudo sed -i "s\# GRAYLOG_HTTP_PROXY_URI = \"\"\GRAYLOG_HTTP_PROXY_URI = \"${SYSTEM_PROXY}\"\g" ${GRAYLOG_ENV}
        sudo sed -i "s\# GRAYLOG_HTTP_NON_PROXY_HOSTS\GRAYLOG_HTTP_NON_PROXY_HOSTS\g" ${GRAYLOG_ENV}
    fi

    sudo sed -i "s\server_name webserver.graylog.test;\server_name ${GRAYLOG_FQDN};\g" ${NGINX_HTTP_CONF}
    sudo sed -i "s\server_name sidecar.graylog.test;\server_name sidecar.${GRAYLOG_FQDN};\g" ${NGINX_HTTP_CONF}

    sudo sed -i "s\hostname: \"samba1\"\hostname: \"${GRAYLOG_FQDN}\"\g" ${GRAYLOG_PATH}/${GRAYLOG_COMPOSE}
    sudo sed -i "s\GF_SERVER_ROOT_URL: \"https://eval.graylog.local/grafana\"\GF_SERVER_ROOT_URL: \"https://${GRAYLOG_FQDN}/grafana\"\g" ${GRAYLOG_PATH}/${GRAYLOG_COMPOSE}

    echo "[INFO] - CONFIGURE SAMBA CONTAINER " | logger -p user.info -e -t GRAYLOG-INSTALLER
    local SHARED_FOLDERS="lookuptables sources"

    for FOLDER in ${SHARED_FOLDERS}
    do  
        sudo chmod -R 755 ${GRAYLOG_PATH}/${FOLDER}
        find ${GRAYLOG_PATH}/${FOLDER}/ -type f -print0 | xargs -0 sudo chmod 644 2>/dev/null >/dev/null
    done

    echo "[INFO] - SET PERMISSIONS FOR HELPER SCRIPTS" | logger -p user.info -e -t GRAYLOG-INSTALLER
    sudo chmod +x ${GRAYLOG_PATH}/sources/scripts/*

    echo "${GRAYLOG_ADMIN}:1000:siem:1000:${GRAYLOG_PASSWORD}" | sudo tee -a "${GRAYLOG_PATH}/samba/users.conf"  >/dev/null 

    echo "[INFO] - REMOVE INSTALLATION FOLDER ${INSTALLPATH^^}" | logger -p user.info -e -t GRAYLOG-INSTALLER
    sudo rm -rf ${INSTALLPATH}
}

function_addScriptRepositoryToPathVariable () {
    echo "[INFO] - ADD SCRIPT FOLDER TO PATH VARIABLE IN /ETC/BASH.BASHRC " | logger -p user.info -e -t GRAYLOG-INSTALLER
    echo "" | sudo tee -a /etc/bash.bashrc 2>/dev/null >/dev/null
    echo "export PATH=${PATH:+${PATH}:}${GRAYLOG_PATH}/sources/scripts" | sudo tee -a /etc/bash.bashrc 2>/dev/null >/dev/null
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
    echo "[INFO] - DOWNLOAD MAXMIND CONTENT " | logger -p user.info -e -t GRAYLOG-INSTALLER
    for DB_TYPE in ${MAXMIND_DB_TYPES}
    do
        sudo curl --output-dir ${GRAYLOG_PATH}/maxmind -LOs https://git.io/GeoLite2-${DB_TYPE}.mmdb
        
        # Alternative Source: 
        # https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-${DB_TYPE}.mmdb 
    done

    echo "[INFO] - DOWNLOAD GRAYLOG SIDECAR FOR WINDOWS " | logger -p user.info -e -t GRAYLOG-INSTALLER
    sudo curl --output-dir ${GRAYLOG_PATH}/sources/binaries/Graylog_Sidecar/MSI -LOs ${SIDECAR_MSI}
    sudo curl --output-dir ${GRAYLOG_PATH}/sources/binaries/Graylog_Sidecar/MSI -LOs ${SIDECAR_YML}
    sudo curl --output-dir ${GRAYLOG_PATH}/sources/binaries/Graylog_Sidecar/EXE -LOs ${SIDECAR_EXE}

    echo "[INFO] - DOWNLOAD FILEBEAT STANDALONE FOR WINDOWS " | logger -p user.info -e -t GRAYLOG-INSTALLER
    sudo curl --output-dir ${GRAYLOG_PATH}/sources/binaries/Filebeat_Standalone -LOs ${FILEBEAT_ZIP}
    sudo curl --output-dir ${GRAYLOG_PATH}/sources/binaries/Filebeat_Standalone -LOs ${FILEBEAT_MSI}
    sudo unzip ${GRAYLOG_PATH}/sources/binaries/Filebeat_Standalone/filebeat-${FILEBEAT_VERSION}-windows-x86_64.zip -d ${GRAYLOG_PATH}/sources/binaries/Filebeat_Standalone/ 2>/dev/null >/dev/null
    sudo cp ${GRAYLOG_PATH}/sources/binaries/Filebeat_Standalone/filebeat-${FILEBEAT_VERSION}-windows-x86_64/filebeat.exe ${GRAYLOG_PATH}/sources/binaries/Filebeat_Standalone/
    sudo rm -rf ${GRAYLOG_PATH}/sources/binaries/Filebeat_Standalone/filebeat-${FILEBEAT_VERSION}-windows-x86_64
    sudo rm ${GRAYLOG_PATH}/sources/binaries/Filebeat_Standalone/filebeat-${FILEBEAT_VERSION}-windows-x86_64.zip

    echo "[INFO] - PREPARE NXLOG COMMUNITY EDITION FOR WINDOWS README FILE " | logger -p user.info -e -t GRAYLOG-INSTALLER
    sudo touch ${GRAYLOG_PATH}/sources/binaries/NXLog_CommunityEdition/README.txt
    echo "DOWNLOAD LOCATION: https://nxlog.co/downloads/nxlog-ce#nxlog-community-edition" | sudo tee -a ${GRAYLOG_PATH}/sources/binaries/NXLog_CommunityEdition/README.txt 2>/dev/null >/dev/null
    echo "INTEGRATION INSTRUCTIONS: https://docs.nxlog.co/integrate/graylog.html" | sudo tee -a ${GRAYLOG_PATH}/sources/binaries/NXLog_CommunityEdition/README.txt 2>/dev/null >/dev/null
}

function_prepareSidecarConfiguration () {
    
    local SIDECAR_TOKEN=${1}
    local SIDECAR_YML="${GRAYLOG_PATH}/sources/binaries/Graylog_Sidecar/MSI/sidecar.yml"
    local SIDECAR_ID=$(curl -s http://localhost/api/users -u ${SIDECAR_TOKEN}:token -X GET -H "X-Requested-By: localhost" | jq .[] | jq '.[] | select(.username=="graylog-sidecar")' | jq -r .id)
    local SIDECAR_INSTALLER_CMD=$(ls "${GRAYLOG_PATH}/sources/binaries/Graylog_Sidecar/EXE" | grep cmd)

    echo "[INFO] - CONFIGURE GRAYLOG SIDECAR FOR WINDOWS (MSI)" | logger -p user.info -e -t GRAYLOG-INSTALLER
    sudo cp ${GRAYLOG_PATH}/sources/binaries/Graylog_Sidecar/MSI/sidecar-windows-msi-example.yml ${SIDECAR_YML}

    # Replace Graylog Host URL
    sudo sed -i "s\#server_url: \"http://127.0.0.1:9000/api/\"\server_url: \"https://${GRAYLOG_FQDN}/api/\"\g" ${SIDECAR_YML}
    # Add Graylog Sidecar Token
    sudo sed -i "s\server_api_token: \"\"\server_api_token: \"${SIDECAR_TOKEN}\"\g" ${SIDECAR_YML}
    # Disable TLS validation enforcement
    sudo sed -i "s\tls_skip_verify: false\tls_skip_verify: true\g" ${SIDECAR_YML}
    # Add Evaluation Tags
    sudo sed -i 's/tags: [[]]/tags:\n  - evaluation\n  - windows\n  - applocker\n  - powershell\n  - defender\n  - rds\n  - forwarded\n  - sysmon\n  - ssh\n  - bpa\n  - bits/g' ${SIDECAR_YML}
    # Change LF to CRLF as this is a Windows Configuration File
    sudo unix2dos ${SIDECAR_YML} 2>/dev/null >/dev/null

    echo "[INFO] - CONFIGURE GRAYLOG SIDECAR FOR WINDOWS (EXE)" | logger -p user.info -e -t GRAYLOG-INSTALLER
    for SIDECAR_INSTALLER in ${SIDECAR_INSTALLER_CMD}
    do
        sudo sed -i "s\SET serverurl=\"\"\SET serverurl=\"https://${GRAYLOG_FQDN}/api/\"\g" ${GRAYLOG_PATH}/sources/binaries/Graylog_Sidecar/EXE/${SIDECAR_INSTALLER}
        sudo sed -i "s\SET apitoken=\"\"\SET apitoken=\"${SIDECAR_TOKEN}\"\g" ${GRAYLOG_PATH}/sources/binaries/Graylog_Sidecar/EXE/${SIDECAR_INSTALLER}
    done
}

function_checkSystemAvailability () {
    while [[ $(curl -s http://localhost/api/system/lbstatus) != "ALIVE" ]]
    do
        echo "[INFO] - WAIT FOR THE SYSTEM TO COME UP "
        sleep 10s
    done
}

function_createUserToken () {

    echo "[INFO] - CREATE GRAYLOG API TOKEN FOR ACCOUNT ${1^^}" | logger -p user.info -e -t GRAYLOG-INSTALLER
    USER_ID=$(curl -s http://localhost/api/users -u "${GRAYLOG_ADMIN}":"${GRAYLOG_PASSWORD}" -X GET -H "X-Requested-By: localhost" | jq .[] | jq ".[] | select(.username == \"${1}\")" | jq -r .id)        
    USER_TOKEN=$(curl -s http://localhost/api/users/${USER_ID}/tokens/evaluation-$1 -u "${GRAYLOG_ADMIN}":"${GRAYLOG_PASSWORD}" -X POST -H "X-Requested-By: localhost)" -H 'Content-Type: application/json' -d "{\"token_ttl\":\"P${2}D\"}" | jq -r .token)
    echo ${USER_TOKEN}

}

function_addSidecarConfigurationVariables () {
    local ADMIN_TOKEN=${1}

    echo "[INFO] - CREATE GRAYLOG SIDECAR CONFIGURATION VARIABLES " | logger -p user.info -e -t GRAYLOG-INSTALLER

    curl -s http://localhost/api/sidecar/configuration_variables -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost)" -H 'Content-Type: application/json' -d '{"id":"","name":"nxlog_port_windows","description":"12148 tcp","content":"12148"}' 2>/dev/null >/dev/null
    curl -s http://localhost/api/sidecar/configuration_variables -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost)" -H 'Content-Type: application/json' -d '{"id":"","name":"beats_port_windows","description":"5044 tcp","content":"5044"}' 2>/dev/null >/dev/null
    curl -s http://localhost/api/sidecar/configuration_variables -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost)" -H 'Content-Type: application/json' -d '{"id":"","name":"beats_port_linux","description":"5045 tcp","content":"5045"}' 2>/dev/null >/dev/null
    curl -s http://localhost/api/sidecar/configuration_variables -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost)" -H 'Content-Type: application/json' -d '{"id":"","name":"beats_port_self","description":"5054 tcp","content":"5054"}' 2>/dev/null >/dev/null

}

function_createBaseConfiguration () {
    
    local ADMIN_TOKEN=${1}

    echo "[INFO] - CREATE INPUT FOR SELF-MONITORING LOGS (GELF UDP 9900)" | logger -p user.info -e -t GRAYLOG-INSTALLER
    local MONITORING_INPUT_GELF=$(curl -s http://localhost/api/system/inputs -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost)" -H 'Content-Type: application/json' -d '{ "global": true, "title": "Port 9900 UDP GELF | Evaluation Input", "type": "org.graylog2.inputs.gelf.udp.GELFUDPInput", "configuration": { "port": 9900, "number_worker_threads": 2, "bind_address": "0.0.0.0" }}'| jq '.id') 

    echo "[INFO] - CREATE INPUT FOR SELF-MONITORING LOGS (BEATS TCP 5054)" | logger -p user.info -e -t GRAYLOG-INSTALLER
    local MONITORING_INPUT_BEATS=$(curl -s http://localhost/api/system/inputs -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost)" -H 'Content-Type: application/json' -d '{ "global": true, "title": "Port 5054 Beats | Evaluation Input for Self-Monitoring", "type": "org.graylog.plugins.beats.Beats2Input", "configuration": { "port": 5054, "number_worker_threads": 2, "bind_address": "0.0.0.0" }}' | jq '.id') 2>/dev/null >/dev/null      

    echo "[INFO] - CREATE FIELD TYPE PROFILE FOR SELF-MONITORING LOGS " | logger -p user.info -e -t GRAYLOG-INSTALLER
    local MONITORING_FIELD_TYPE_PROFILE=$(curl -s http://localhost/api/system/indices/index_sets/profiles -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{ "custom_field_mappings":[{ "field": "command", "type": "string" }, { "field": "container_name", "type": "string" }, { "field": "image_name", "type": "string" }, { "field": "container_name", "type": "string" }], "name": "Self Monitoring Messages (Evaluation)", "description": "Field Mappings for Self Monitoring Messages" }' | jq '.id')

    echo "[INFO] - CREATE INDEX FOR SELF-MONITORING LOGS " | logger -p user.info -e -t GRAYLOG-INSTALLER
    local MONITORING_INDEX=$(curl -s http://localhost/api/system/indices/index_sets -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d "{\"shards\": 1, \"replicas\": 0, \"rotation_strategy_class\": \"org.graylog2.indexer.rotation.strategies.TimeBasedSizeOptimizingStrategy\", \"rotation_strategy\": {\"type\": \"org.graylog2.indexer.rotation.strategies.TimeBasedSizeOptimizingStrategyConfig\", \"index_lifetime_min\": \"P30D\", \"index_lifetime_max\": \"P90D\"}, \"retention_strategy_class\": \"org.graylog2.indexer.retention.strategies.DeletionRetentionStrategy\", \"retention_strategy\": { \"type\": \"org.graylog2.indexer.retention.strategies.DeletionRetentionStrategyConfig\", \"max_number_of_indices\": 20 }, \"data_tiering\": {\"type\": \"hot_only\", \"index_lifetime_min\": \"P30D\", \"index_lifetime_max\": \"P90D\"}, \"title\": \"Self Monitoring Messages (Evaluation)\", \"description\": \"Stores Evaluation System Self Monitoring Messages\", \"index_prefix\": \"gl-self-monitoring\", \"index_analyzer\": \"standard\", \"index_optimization_max_num_segments\": 1, \"index_optimization_disabled\": false, \"field_type_refresh_interval\": 5000, \"field_type_profile\": ${MONITORING_FIELD_TYPE_PROFILE}, \"use_legacy_rotation\": false, \"writable\": true}" | jq '.id')

    echo "[INFO] - CREATE STREAM FOR SELF-MONITORING LOGS " | logger -p user.info -e -t GRAYLOG-INSTALLER
    local MONITORING_STREAM=$(curl -s http://localhost/api/streams -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d "{\"entity\": { \"description\": \"Stream containing all self monitoring events created by Docker\", \"title\": \"System Self Monitoring (Evaluation)\", \"remove_matches_from_default_stream\": true, \"matching_type\": \"OR\", \"index_set_id\": ${MONITORING_INDEX} }}" | jq -r '.stream_id') 2>/dev/null >/dev/null

    echo "[INFO] - CREATE STREAM RULE FOR SELF-MONITORING LOGS (GELF) " | logger -p user.info -e -t GRAYLOG-INSTALLER
    curl -s http://localhost/api/streams/${MONITORING_STREAM}/rules -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d "{ \"field\": \"gl2_source_input\", \"description\": \"Self Monitoring Logs\", \"type\": 1, \"inverted\": false, \"value\": ${MONITORING_INPUT_GELF} }" 2>/dev/null >/dev/null

    echo "[INFO] - CREATE STREAM RULE FOR SELF-MONITORING LOGS (BEATS) " | logger -p user.info -e -t GRAYLOG-INSTALLER
    curl -s http://localhost/api/streams/${MONITORING_STREAM}/rules -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d "{ \"field\": \"gl2_source_input\", \"description\": \"Self Monitoring Logs\", \"type\": 1, \"inverted\": false, \"value\": ${MONITORING_INPUT_BEATS} }" 2>/dev/null >/dev/null

    echo "[INFO] - START STREAM FOR SELF-MONITORING LOGS " | logger -p user.info -e -t GRAYLOG-INSTALLER
    curl -s http://localhost/api/streams/${MONITORING_STREAM}/resume -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost" 2>/dev/null >/dev/null

    echo "[INFO] - ACTIVATE OTX PLUGIN " | logger -p user.info -e -t GRAYLOG-INSTALLER
    curl -s http://localhost/api/system/content_packs/daf6355e-2d5e-08d3-f9ba-44e84a43df1a/1/installations -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{"entity":{"parameters":{},"comment":"Activated for Evaluation"}}' 2>/dev/null >/dev/null

    echo "[INFO] - ACTIVATE TOR EXIT NODES LIST " | logger -p user.info -e -t GRAYLOG-INSTALLER
    curl -s http://localhost/api/system/content_packs/9350a70a-8453-f516-7041-517b4df0b832/1/installations -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{"entity":{"parameters":{},"comment":"Activated for Evaluation"}}' 2>/dev/null >/dev/null

    echo "[INFO] - ACTIVATE SPAMHAUS DROP LISTS " | logger -p user.info -e -t GRAYLOG-INSTALLER
    curl -s http://localhost/api/system/content_packs/90be5e03-cb16-c802-6462-a244b4a342f3/1/installations -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{"entity":{"parameters":{},"comment":"Activated for Evaluation"}}' 2>/dev/null >/dev/null

    echo "[INFO] - ACTIVATE WHOIS PLUGIN " | logger -p user.info -e -t GRAYLOG-INSTALLER
    curl -s http://localhost/api/system/content_packs/1794d39d-077f-7360-b92b-95411b05fbce/1/installations -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{"entity":{"parameters":{},"comment":"Activated for Evaluation"}}' 2>/dev/null >/dev/null

    echo "[INFO] - ACTIVATE GEOIP PLUGIN " | logger -p user.info -e -t GRAYLOG-INSTALLER
    curl -s http://localhost/api/system/cluster_config/org.graylog.plugins.map.config.GeoIpResolverConfig -u ${ADMIN_TOKEN}:token -X PUT -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{ "enabled":true,"enforce_graylog_schema":true,"db_vendor_type":"MAXMIND","city_db_path":"/etc/graylog/server/mmdb/GeoLite2-City.mmdb","asn_db_path":"/etc/graylog/server/mmdb/GeoLite2-ASN.mmdb","refresh_interval_unit":"DAYS","refresh_interval":14,"use_s3":false }' 2>/dev/null >/dev/null

    echo "[INFO] - ACTIVATE THREAT INTEL PLUGIN " | logger -p user.info -e -t GRAYLOG-INSTALLER
    curl -s http://localhost/api/system/cluster_config/org.graylog.plugins.threatintel.ThreatIntelPluginConfiguration -u ${ADMIN_TOKEN}:token -X PUT -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{"tor_enabled":true,"spamhaus_enabled":true,"abusech_ransom_enabled":false}' 2>/dev/null >/dev/null

    echo "[INFO] - REARRANGE PROCESSING ORDER AND DISABLE AWS INSTANCE NAME LOOKUP" | logger -p user.info -e -t GRAYLOG-INSTALLER
    curl -s http://localhost/api/system/messageprocessors/config -u ${ADMIN_TOKEN}:token -X PUT -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{"processor_order":[{"name":"AWS Instance Name Lookup","class_name":"org.graylog.aws.processors.instancelookup.AWSInstanceNameLookupProcessor"},{"name":"Illuminate Processor","class_name":"org.graylog.plugins.illuminate.processing.IlluminateMessageProcessor"},{"name":"Message Filter Chain","class_name":"org.graylog2.messageprocessors.MessageFilterChainProcessor"},{"name":"Stream Rule Processor","class_name":"org.graylog2.messageprocessors.StreamMatcherFilterProcessor"},{"name":"Pipeline Processor","class_name":"org.graylog.plugins.pipelineprocessor.processors.PipelineInterpreter"},{"name":"GeoIP Resolver","class_name":"org.graylog.plugins.map.geoip.processor.GeoIpProcessor"}],"disabled_processors":["org.graylog.aws.processors.instancelookup.AWSInstanceNameLookupProcessor"]}' 2>/dev/null >/dev/null

    echo "[INFO] - RECONFIGURE GRAFANA CREDENTIALS " | logger -p user.info -e -t GRAYLOG-INSTALLER
    curl -s http://admin:admin@localhost/grafana/api/users/1 -H 'Content-Type:application/json' -X PUT -d "{ \"name\" : \"Evaluation Admin\", \"login\" : \"${GRAYLOG_ADMIN}\" }" 2>/dev/null >/dev/null 
    curl -s http://${GRAYLOG_ADMIN}:admin@localhost/grafana/api/admin/users/1/password -H 'Content-Type: application/json' -X PUT -d "{ \"password\" : \"$GRAYLOG_PASSWORD\" }" 2>/dev/null >/dev/null 

    echo "[INFO] - CONFIGURE PROMETHEUS CONNECTOR " | logger -p user.info -e -t GRAYLOG-INSTALLER
    curl -s http://${GRAYLOG_ADMIN}:$GRAYLOG_PASSWORD@localhost/grafana/api/datasources -H 'Content-Type: application/json' -X POST -d '{ "name" : "prometheus", "type" : "prometheus", "url": "http://prometheus1:9090/prometheus", "access": "proxy", "readOnly" : false, "isDefault" : true, "basicAuth" : false }' 2>/dev/null >/dev/null
}

function_displayClusterId () {

    echo "  ADMINUSER: \"${GRAYLOG_ADMIN}\" 
            PASSWORD: \"${GRAYLOG_PASSWORD}\"
        " | sudo tee ${GRAYLOG_PATH}/your_graylog_credentials.txt 2>/dev/null >/dev/null

    echo "[INFO] - GRAYLOG IS NOW READY FOR TESTING"
    echo -e "[INFO] - SYSTEM URL: \e[4;33mhttp(s)://${GRAYLOG_FQDN}\e[0m"
    echo -e "[INFO] - WINDOWS ACCESS: \e[1;32m\\\\\\\\${GRAYLOG_FQDN}\e[0m (SMB)"
    echo -e "[INFO] - CREDENTIALS STORED IN: \e[0;37m${GRAYLOG_PATH}/your_graylog_credentials.txt\e[0m"    
    echo -e "[INFO] - FOR ADDITIONAL CONFIGURATIONS PLEASE DO REVIEW: \e[0;37m${GRAYLOG_PATH}/graylog.env\e[0m"
    echo ""
    echo "       ******************************************************"
    echo "       *                                                    *"
    echo -e "       * CLUSTER-ID: \e[1;31m$(curl -s localhost/api | jq '.cluster_id' | tr a-z A-Z )\e[0m *"
    echo "       *                                                    *"
    echo "       ******************************************************"
    echo ""
    echo "[INFO] - GRAYLOG STACK WILL RESTART AFTER ADDING THE LICENSE"
}

function_checkEnterpriseLicense () {

    local ADMIN_TOKEN=${1}
    local LICENSE_ENTERPRISE="false"

    while [[ ${LICENSE_ENTERPRISE} != "true" ]]
    do 
        LICENSE_ENTERPRISE=$(curl -H 'Cache-Control: no-cache, no-store' -s http://localhost/api/plugins/org.graylog.plugins.license/licenses/status -u ${ADMIN_TOKEN}:token | jq .[] | jq '.[] | select(.active == true and .license.subject == "/license/enterprise")' | jq -r .active )
        echo "[INFO] - WAIT FOR ENTERPRISE LICENSE TO BE AVAILABLE " | logger -p user.info -e -t GRAYLOG-INSTALLER
        sleep 15s
    done

    echo "${LICENSE_ENTERPRISE}"
}

function_checkSecurityLicense () {

    local ADMIN_TOKEN=${1}
    local LICENSE_SECURITY="false"

    while [[ ${LICENSE_SECURITY} != "true" ]]
    do 
        LICENSE_SECURITY=$(curl -H 'Cache-Control: no-cache, no-store' -s http://localhost/api/plugins/org.graylog.plugins.license/licenses/status -u ${ADMIN_TOKEN}:token | jq .[] | jq '.[] | select(.active == true and .license.subject == "/license/security")' | jq -r .active )
        echo "[INFO] - WAIT FOR SECURITY LICENSE TO BE AVAILABLE " | logger -p user.info -e -t GRAYLOG-INSTALLER
        sleep 15s
    done

    echo "${LICENSE_SECURITY}"
}

function_restartGraylogContainer () {

    local GRAYLOG_CONTAINER=${1}

    echo "[INFO] - STOP CONTAINER ${1^^} " | logger -p user.info -e -t GRAYLOG-INSTALLER
    sudo docker compose -f ${GRAYLOG_PATH}/docker-compose.yaml down ${1} 2>/dev/null >/dev/null
    echo "[INFO] - START CONTAINER ${1^^} " | logger -p user.info -e -t GRAYLOG-INSTALLER
    sudo docker compose -f ${GRAYLOG_PATH}/docker-compose.yaml up -d ${1} 2>/dev/null >/dev/null
}

function_startGraylogStack () {
    echo "[INFO] - START GRAYLOG STACK " | logger -p user.info -e -t GRAYLOG-INSTALLER
    sudo docker compose -f ${GRAYLOG_PATH}/docker-compose.yaml up -d --quiet-pull --remove-orphans 2>/dev/null >/dev/null
}

function_stopGraylogStack () {
    echo "[INFO] - STOP GRAYLOG STACK " | logger -p user.info -e -t GRAYLOG-INSTALLER
    sudo docker compose -f ${GRAYLOG_PATH}/docker-compose.yaml down --remove-orphans 2>/dev/null >/dev/null
}

function_createInputs () {

    local ADMIN_TOKEN=${1}
    local INPUT_ID_SELF_MONITORING_GELF=$(curl -s http://localhost/api/system/inputs -u ${ADMIN_TOKEN}:token -X GET -H "X-Requested-By: localhost" -H 'Content-Type: application/json' | jq .inputs | jq '.[] | select(.attributes.port==9900)' | jq -r .id )
    local INPUT_ID_SELF_MONITORING_BEATS=$(curl -s http://localhost/api/system/inputs -u ${ADMIN_TOKEN}:token -X GET -H "X-Requested-By: localhost" -H 'Content-Type: application/json' | jq .inputs | jq '.[] | select(.attributes.port==5054)' | jq -r .id )

    if [ "${GRAYLOG_LICENSE_ENTERPRISE}" == "true" ]
    then    
        echo "[INFO] - CREATE EVALUATION INPUTS " | logger -p user.info -e -t GRAYLOG-INSTALLER
        # Adding Inputs to make sure Ports map to Nginx configuration
        #
        # Port 514 Syslog UDP Input for Network Devices
        curl -s http://localhost/api/system/inputs -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost)" -H 'Content-Type: application/json' -d '{ "global": true, "title": "Port 514 UDP Syslog | Evaluation Input", "type": "org.graylog2.inputs.syslog.udp.SyslogUDPInput", "configuration": { "port": 514, "number_worker_threads": 2, "bind_address": "0.0.0.0" }}' 2>/dev/null >/dev/null

        # Port 514 Syslog TCP Input for Network Devices
        curl -s http://localhost/api/system/inputs -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost)" -H 'Content-Type: application/json' -d '{ "global": true, "title": "Port 514 TCP Syslog | Evaluation Input", "type": "org.graylog2.inputs.syslog.tcp.SyslogTCPInput", "configuration": { "port": 514, "number_worker_threads": 2, "bind_address": "0.0.0.0" }}' 2>/dev/null >/dev/null

        # Port 5044 Beats Input for Winlogbeat, Auditbeat, Filebeat
        curl -s http://localhost/api/system/inputs -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost)" -H 'Content-Type: application/json' -d '{ "global": true, "title": "Port 5044 Beats | Evaluation Input", "type": "org.graylog.plugins.beats.Beats2Input", "configuration": { "port": 5044, "number_worker_threads": 2, "bind_address": "0.0.0.0" }}' 2>/dev/null >/dev/null
        
        # Port 5555 RAW TCP Input
        curl -s http://localhost/api/system/inputs -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost)" -H 'Content-Type: application/json' -d '{ "global": true, "title": "Port 5555 TCP RAW | Evaluation Input", "type": "org.graylog2.inputs.raw.tcp.RawTCPInput", "configuration": { "port": 5555, "number_worker_threads": 2, "bind_address": "0.0.0.0" }}' 2>/dev/null >/dev/null
            
        # Port 5555 RAW UDP Input
        curl -s http://localhost/api/system/inputs -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost)" -H 'Content-Type: application/json' -d '{ "global": true, "title": "Port 5555 UDP RAW | Evaluation Input", "type": "org.graylog2.inputs.raw.udp.RawUDPInput", "configuration": { "port": 5555, "number_worker_threads": 2, "bind_address": "0.0.0.0" }}' 2>/dev/null >/dev/null

        # Port 6514 Syslog TCP over TLS Input for Network Devices
        curl -s http://localhost/api/system/inputs -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost)" -H 'Content-Type: application/json' -d '{ "global": true, "title": "Port 6514 TCP Syslog over TLS | Evaluation Input", "type": "org.graylog2.inputs.syslog.tcp.SyslogTCPInput", "configuration": { "port": 6514, "number_worker_threads": 2, "bind_address": "0.0.0.0", "tls_cert_file": "/etc/graylog/server/input_tls/cert.crt", "tls_key_file": "/etc/graylog/server/input_tls/tls.key", "tls_enable": false, "tls_key_password": "" }}' 2>/dev/null >/dev/null

        # Port 12201 GELF TCP Input for NXLog
        curl -s http://localhost/api/system/inputs -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost)" -H 'Content-Type: application/json' -d '{ "global": true, "title": "Port 12201 TCP GELF | Evaluation Input", "type": "org.graylog2.inputs.gelf.tcp.GELFTCPInput", "configuration": { "port": 12201, "number_worker_threads": 2, "bind_address": "0.0.0.0" }}' 2>/dev/null >/dev/null

        # Port 12201 GELF UDP Input for NXLog
        curl -s http://localhost/api/system/inputs -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost)" -H 'Content-Type: application/json' -d '{ "global": true, "title": "Port 12201 UDP GELF | Evaluation Input", "type": "org.graylog2.inputs.gelf.udp.GELFUDPInput", "configuration": { "port": 12201, "number_worker_threads": 2, "bind_address": "0.0.0.0" }}' 2>/dev/null >/dev/null

        # Port 13301 13302 TCP Input for Enterprise Forwarder 
        curl -s http://localhost/api/system/inputs -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost)" -H 'Content-Type: application/json' -d '{"type":"org.graylog.plugins.forwarder.input.ForwarderServiceInput","configuration":{"forwarder_bind_address":"0.0.0.0","forwarder_message_transmission_port":13301,"forwarder_configuration_port":13302,"forwarder_grpc_enable_tls":false,"forwarder_grpc_tls_trust_chain_cert_file":"","forwarder_grpc_tls_private_key_file":"","forwarder_grpc_tls_private_key_file_password":""},"title":"Graylog Enterprise Forwarder | Evaluation Input","global":true}' 2>/dev/null >/dev/null

        echo "[INFO] - STOP EVALUATION INPUTS EXCEPT THE ONE FOR SELF-MONITORING " | logger -p user.info -e -t GRAYLOG-INSTALLER
        # Stopping all Inputs to allow a controlled Log Source Onboarding (except Self_monitoring Input)
        for INPUT in $(curl -s http://localhost/api/cluster/inputstates -u ${ADMIN_TOKEN}:token -X GET | jq -r '.[] | map(.) | .[].id')
        do
            if [ ${INPUT} != ${INPUT_ID_SELF_MONITORING_GELF} ] && [ ${INPUT} != ${INPUT_ID_SELF_MONITORING_BEATS} ]
            then
                curl -s http://localhost/api/cluster/inputstates/${INPUT} -u ${ADMIN_TOKEN}:token -X DELETE -H "X-Requested-By: localhost" -H 'Content-Type: application/json' 2>/dev/null >/dev/null
            fi
        done
    fi
}

function_createEvaluationConfiguration () {

    local ADMIN_TOKEN=${1}
    local SELF_MONITORING_STREAM=$(curl -s http://localhost/api/streams -u ${ADMIN_TOKEN}:token -X GET -H "X-Requested-By: localhost" -H 'Content-Type: application/json' | jq .streams | jq '.[] | select(.title == "System Self Monitoring (Evaluation)")' | jq -r .id)
 
    if [ "${GRAYLOG_LICENSE_ENTERPRISE}" == "true" ]
    then        
        echo "[INFO] - ENABLE HEADER BADGE " | logger -p user.info -e -t GRAYLOG-INSTALLER
        curl -s http://localhost/api/system/cluster_config/org.graylog.plugins.customization.HeaderBadge -u ${ADMIN_TOKEN}:token -X PUT -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{"badge_enable": true,"badge_color": "#689f38","badge_text": "EVAL"}' 2>/dev/null >/dev/null  
        
        echo "[INFO] - ENABLE EVALUATION NOTIFICATION " | logger -p user.info -e -t GRAYLOG-INSTALLER
        curl -s http://localhost/api/plugins/org.graylog.plugins.customization/notifications -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{"title":"Evaluation System","shortMessage":"DO NOT USE IN PRODUCTION","longMessage":"This System was set up for a Graylog Product Evaluation and MUST NOT be used in production. For a secure and production-ready setup please get in touch with your Graylog Customer Success Manager who will help you to deploy your Graylog Stack following best practices.","isActive":true,"isDismissible":true,"atLogin":true,"isGlobal":false,"variant":"warning","hiddenTitle":false}' 2>/dev/null >/dev/null
        
        echo "[INFO] - ENABLE GRAYLOG v5 COLOUR SCHEME " | logger -p user.info -e -t GRAYLOG-INSTALLER
        # curl -s http://localhost/api/plugins/org.graylog.plugins.customization/theme -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{"light":{"global":{"background":"#eeeff2","link":"#578dcc"},"brand":{"tertiary":"#3e434c"},"variant":{"default":"#9aa8bd","danger":"#eb5454","info":"#578dcc","primary":"#697586","success":"#7eb356","warning":"#eedf64"}},"dark":{"global":{"background":"#222222","contentBackground":"#303030","link":"#629de2"},"brand":{"tertiary":"#ffffff"},"variant":{"default":"#595959","danger":"#e74c3c","info":"#578dcc","primary":"#697586","success":"#709e4c","warning":"#e3d45f"}}}' 2>/dev/null >/dev/null
  
        echo "[INFO] - CONFIGURE ARCHIVE " | logger -p user.info -e -t GRAYLOG-INSTALLER
        local ARCHIVE_BACKEND=$(curl -s http://localhost/api/plugins/org.graylog.plugins.archive/config -u ${ADMIN_TOKEN}:token -X GET -H "X-Requested-By: localhost" -H 'Content-Type: application/json' | jq -r .backend_id)

        curl -s http://localhost/api/plugins/org.graylog.plugins.archive/config -u ${ADMIN_TOKEN}:token -X PUT -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d "{\"archive_path\": \"/usr/share/graylog/data/archives\",\"max_segment_size\": 524288000,\"segment_filename_prefix\": \"archive-segment\",\"segment_compression_type\": \"GZIP\",\"metadata_filename\": \"archive-metadata.json\",\"histogram_bucket_size\": 86400000,\"restore_index_batch_size\": 1000,\"excluded_streams\": [],\"segment_checksum_type\": \"CRC32\",\"backend_id\": \"${ARCHIVE_BACKEND}\",\"archive_failure_threshold\": 1,\"retention_time\": 30,\"restrict_to_leader\": true,\"parallelize_archive_creation\": true}" 2>/dev/null >/dev/null

        echo "[INFO] - ENABLE WARM TIER (LOCAL FILESTORE OR MOUNTPOINT) " | logger -p user.info -e -t GRAYLOG-INSTALLER
        WARM_TIER_NAME=$(curl -s http://localhost/api/plugins/org.graylog.plugins.datatiering/datatiering/repositories -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{"type":"fs","name":"warm_tier","location":"/usr/share/opensearch/warm_tier"}' | jq -r .name) 2>/dev/null >/dev/null

        echo "[INFO] - CREATE INDEX SET TEMPLATE FOR EVALUATION (SHORT RETENTION) " | logger -p user.info -e -t GRAYLOG-INSTALLER
        INDEX_SET_TEMPLATE=$(curl -s http://localhost/api/system/indices/index_sets/templates -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d "{\"title\": \"Evaluation Storage\",\"description\": \"Use case: Graylog Product Evaluation\",\"index_set_config\": {\"shards\": 1,\"replicas\": 0,\"index_optimization_max_num_segments\": 1,\"index_optimization_disabled\": false,\"field_type_refresh_interval\": 5000,\"data_tiering\": {\"type\": \"hot_warm\",\"index_lifetime_min\": \"P7D\",\"index_lifetime_max\": \"P10D\",\"warm_tier_enabled\": true,\"index_hot_lifetime_min\": \"P3D\",\"warm_tier_repository_name\": \"${WARM_TIER_NAME}\",\"archive_before_deletion\": true},\"index_analyzer\": \"standard\",\"use_legacy_rotation\": false}}" | jq -r .id) 

        echo "[INFO] - CONFIGURE INDEX SET TEMPLATE FOR EVALUATION AS DEFAULT " | logger -p user.info -e -t GRAYLOG-INSTALLER
        curl -s http://localhost/api/system/indices/index_set_defaults -u ${ADMIN_TOKEN}:token -X PUT -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d "{\"id\":\"${INDEX_SET_TEMPLATE}\"}" 2>/dev/null >/dev/null

        echo "[INFO] - ENABLE DATALAKE (LOCAL FILESTORE OR MOUNTPOINT) " | logger -p user.info -e -t GRAYLOG-INSTALLER
        ACTIVE_BACKEND=$(curl -s http://localhost/api/plugins/org.graylog.plugins.datalake/data_lake/backends -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d '{"title":"File System Data Lake","description":"Data Lake on the local Filesystem","settings":{"type":"fs-1","output_path":"/usr/share/graylog/data/datalake","usage_threshold":80}}' | jq -r .id) 2>/dev/null >/dev/null

        echo "[INFO] - ACTIVATE DATALAKE (LOCAL FILESTORE OR MOUNTPOINT) " | logger -p user.info -e -t GRAYLOG-INSTALLER
        curl -s http://localhost/api/plugins/org.graylog.plugins.datalake/data_lake/config -u ${ADMIN_TOKEN}:token -X PUT -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d "{\"active_backend\":\"${ACTIVE_BACKEND}\",\"iceberg_commit_interval\":\"PT15M\",\"iceberg_target_file_size\":536870912,\"parquet_row_group_size\":134217728,\"parquet_page_size\":8192,\"journal_reader_batch_size\":500,\"optimize_job_enabled\":true,\"optimize_job_interval\":\"PT1H\",\"optimize_max_concurrent_file_rewrites\":null,\"parallel_retrieval_enabled\":true,\"retrieval_convert_threads\":-1,\"retrieval_convert_batch_size\":1,\"retrieval_inflight_requests\":3,\"retrieval_bulk_batch_size\":2500,\"retention_time\":null}" 2>/dev/null >/dev/null

        echo "[INFO] - CONFIGURE DATALAKE MAX RETENTION (7 DAYS) " | logger -p user.info -e -t GRAYLOG-INSTALLER
        curl -s http://localhost/api/plugins/org.graylog.plugins.datalake/data_lake/config -u ${ADMIN_TOKEN}:token -X PUT -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d "{\"active_backend\":\"${ACTIVE_BACKEND}\",\"iceberg_commit_interval\":\"PT15M\",\"iceberg_target_file_size\":536870912,\"parquet_row_group_size\":134217728,\"parquet_page_size\":8192,\"journal_reader_batch_size\":500,\"optimize_job_enabled\":true,\"optimize_job_interval\":\"PT1H\",\"optimize_max_concurrent_file_rewrites\":null,\"parallel_retrieval_enabled\":true,\"retrieval_convert_threads\":-1,\"retrieval_convert_batch_size\":1,\"retrieval_inflight_requests\":3,\"retrieval_bulk_batch_size\":2500,\"retention_time\":\"P7D\"}" 2>/dev/null >/dev/null

        echo "[INFO] - CONFIGURE DATALAKE FOR SELF-MONITORING STREAM " | logger -p user.info -e -t GRAYLOG-INSTALLER
        curl -s http://localhost/api/plugins/org.graylog.plugins.datalake/data_lake/stream/config/enable -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d "{\"stream_ids\":[\"${SELF_MONITORING_STREAM}\"],\"enabled\":true}" 2>/dev/null >/dev/null
    fi
    
}

function_enableIlluminatePackages () {

    local ADMIN_TOKEN=${1}
    local ILLUMINATE_PROCESSING_PACK_IDS='["illuminate-defender","b1f235ed-f185-43af-b5d1-d3fb37f217a1","73788c38-0b74-4c03-8b69-2fcb4e110a9b","659b983d-9654-4141-a672-87dee3ee8176","d1aea731-2b18-4e47-9366-c526641f6dbd","illuminate-sysmon","5551b8a8-6459-446f-9ea8-63368bb39414","2e6cedfb-21f9-485f-8bdc-326349651b0f","windows-security","c3c902ad-9113-439e-b92b-5cd4bfa26696","3c5c2c47-18a5-4054-9f0e-2443f6d96d02","0137f1f8-1a6e-449b-a46c-6bb37f2f0c53","3f3c1eea-200a-4381-83ae-aadd5d6a0d6e","7b319ad0-352c-48b9-b7d9-877fc1720164","core-gim-enforcement"]'
    local ILLUMINATE_SPOTLIGHT_PACK_IDS='["f39f9b0d-c24b-42f2-982b-839441ef3c27","e1629dcb-6419-4d73-b4a8-577f01278f35","a60c3607-a25a-4b5c-a565-94b6944f850b","b95c89b7-36e1-43b6-9714-b6b25e7cec04e","61d75c3e-3551-4b97-bbb5-ea8181472cb0","a2750c63-fb7c-4ff6-b10b-32171a2c96e9","4e3ba1a6-7400-40d1-b7f8-efa44bc5bfeb","cbfc3ae6-6a59-4841-a691-ea6db41b62d0","d01d7647-99a5-4914-b417-ca5cd1e37196","085d8f0e-2bee-44b2-b040-d7a11a1da2fe","90e37be0-d112-44f8-afe7-eadcafbe4ba3","52391e38-df23-4953-86e5-44e2bc667b97","66e7f007-6f77-45dc-a6f3-94cb3745541e","237e73a4-678b-4b9a-87ac-ff2f86e34563","3e40d288-5794-44e9-88b4-b590de3514b8","9f195288-9709-4f87-b2ec-e53cf94965dd","a9463b48-f009-4641-84e8-4245d3dc6e89"]'

    if [ "${GRAYLOG_LICENSE_ENTERPRISE}" == "true" ]
    then
        echo "[INFO] - ENABLE ILLUMINATE PACKAGES " | logger -p user.info -e -t GRAYLOG-INSTALLER
        curl -s http://localhost/api/plugins/org.graylog.plugins.illuminate/bundles/latest/enable_packs -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d "{\"entity\":{\"processing_pack_ids\":${ILLUMINATE_PROCESSING_PACK_IDS},\"spotlight_pack_ids\":${ILLUMINATE_SPOTLIGHT_PACK_IDS}}}" 2>/dev/null >/dev/null
    fi
}

function_enableGraylogSidecar () {

    local SIDECAR_TOKEN=${1}
    
    echo "[INFO] - ENABLE AND START GRAYLOG SIDECAR ON HOST " | logger -p user.info -e -t GRAYLOG-INSTALLER
    sudo graylog-sidecar -service install 2>/dev/null >/dev/null
    sudo systemctl enable graylog-sidecar 2>/dev/null >/dev/null
    sudo systemctl start graylog-sidecar 2>/dev/null >/dev/null
}

function_configureSecurityFeatures () {

    local ADMIN_TOKEN=${1}
    
    if [[ "$GRAYLOG_LICENSE_SECURITY" == "true" ]]
    then
        local ACTIVE_AI_REPORT=""
        local ILLUMINATE_SECURITY_PROCESSING_PACK_IDS='["core_anomaly_detection","05dc479f-9659-476b-b888-9fdaae3a7777"]'
        local ILLUMINATE_SECURITY_SPOTLIGHT_PACK_IDS='["5289b02d-ebb9-4c93-baf8-baf05e1c138b","10da1609-54b1-4e73-8757-a5326379ad26","85411e45-52b4-4a4c-8b03-a26be9900a28","759a0e52-e76a-4836-889a-1bab2fce65d3","6f6197cf-ee3f-453b-a248-c309ff91ed0a","019b5712-186d-440b-afd8-88386b1411f9","8f445386-5dfe-4d64-a790-f7a6527789b7"]'    
        
        while [[ ${ACTIVE_AI_REPORT} == "true" ]] || [[ ${ACTIVE_AI_REPORT} == "" ]]
        do 
            echo "[INFO] - DISABLE INVESTIGATION AI REPORTS " | logger -p user.info -e -t GRAYLOG-INSTALLER
            curl -s http://localhost/api/plugins/org.graylog.plugins.securityapp.investigations/ai/config/investigations_ai_reports_enabled -u ${ADMIN_TOKEN}:token -X DELETE -H "X-Requested-By: localhost" 2>/dev/null >/dev/null
            ACTIVE_AI_REPORT=$(curl -s http://localhost/api/plugins/org.graylog.plugins.securityapp.investigations/ai/config -u ${ADMIN_TOKEN}:token -X GET -H "X-Requested-By: localhost" | jq .investigations_ai_reports_enabled) 2>/dev/null >/dev/null
        done

        echo "[INFO] - ENABLE ILLUMINATE SECURITY PACKAGES " | logger -p user.info -e -t GRAYLOG-INSTALLER
        curl -s http://localhost/api/plugins/org.graylog.plugins.illuminate/bundles/latest/enable_packs -u ${ADMIN_TOKEN}:token -X POST -H "X-Requested-By: localhost" -H 'Content-Type: application/json' -d "{\"entity\":{\"processing_pack_ids\":${ILLUMINATE_SECURITY_PROCESSING_PACK_IDS},\"spotlight_pack_ids\":${ILLUMINATE_SECURITY_SPOTLIGHT_PACK_IDS}}}" 2>/dev/null >/dev/null 
    fi 

}


###############################################################################
#
# Graylog Installation
if [[ $(cat ${GRAYLOG_PATH}/.installation 2>/dev/null) == "started" ]]
then
    echo "[INFO] - INSTALLATION WAS INTERRUPTED, RESET TO SNAPSHOT AND START AGAIN" 
    read -p "press enter to continue..."
    exit 
elif [[ $(cat ${GRAYLOG_PATH}/.installation 2>/dev/null) == "" ]]
then
    function_checkInternetConnectivity

    sudo mkdir -p ${GRAYLOG_PATH}
    
    clear

    echo "[INFO] - GET SYSTEM PREPARED FOR INSTALLATION, HANG ON"
    function_installScriptDependencies
       
    function_checkSnapshot
    function_defineAdminName
    function_defineAdminPassword
    function_getSystemFqdn

    function_checkSystemRequirements

    echo "started" | sudo tee ${GRAYLOG_PATH}/.installation 2>/dev/null >/dev/null
    echo "[INFO] - INSTALL DOCKER-CE"
    function_installDocker

    echo "[INFO] - INSTALL GRAYLOG STACK, GIVE IT SOME TIME"
    function_installGraylogStack
    function_startGraylogStack
    function_addScriptRepositoryToPathVariable

    echo "[INFO] - PREPARE ADDITIONAL CONTENT"
    function_downloadAdditionalBinaries
    function_checkSystemAvailability

    GRAYLOG_ADMIN_TOKEN=$(function_createUserToken $GRAYLOG_ADMIN 14)
    GRAYLOG_SIDECAR_TOKEN=$(function_createUserToken $GRAYLOG_SIDECAR 730)

    echo "[INFO] - INSTALL SIDECAR ON HOST"
    function_installGraylogSidecar ${GRAYLOG_SIDECAR_TOKEN}
    function_addSidecarConfigurationVariables ${GRAYLOG_ADMIN_TOKEN}

    echo "[INFO] - PREPARE SYSTEM PLUGINS AND FUNCTIONS"
    function_createBaseConfiguration ${GRAYLOG_ADMIN_TOKEN}
    function_prepareSidecarConfiguration ${GRAYLOG_SIDECAR_TOKEN}

    # Make sure the Container being restarted is the LEADER node, as the automatic Content Pack installation is executed by the LEADER
    function_restartGraylogContainer graylog1

    function_displayClusterId

    echo "[INFO] - NOW IT'S UP TO YOU PREPARING YOUR LOG SOURCES"
    
    echo "completed" | sudo tee ${GRAYLOG_PATH}/.installation 2>/dev/null >/dev/null
    echo "${GRAYLOG_ADMIN_TOKEN}" | sudo tee ${GRAYLOG_PATH}/.admintoken 2>/dev/null >/dev/null 

    sudo cp $0 /etc/cron.hourly/install-graylog
    sudo rm -- $0

    echo "[INFO] - BASE INSTALLATION SUCCESSFULLY FINISHED, WAITING FOR LICENSE" | logger -p user.info -e -t GRAYLOG-INSTALLER

    exit
fi


###############################################################################
#
# Post-Installation Tasks

if [[ $(cat ${GRAYLOG_PATH}/.installation 2>/dev/null) == "completed" ]]
then
    echo "continued" | sudo tee ${GRAYLOG_PATH}/.installation 2>/dev/null 

    sudo rm -- ${0}
    sudo rm ${GRAYLOG_PATH}/.installation ${GRAYLOG_PATH}/.admintoken

    GRAYLOG_LICENSE_ENTERPRISE=$(function_checkEnterpriseLicense ${GRAYLOG_ADMIN_TOKEN}) 

    echo "[INFO] - RESTARTING GRAYLOG STACK FOR MAINTENANCE PURPOSES" | logger -p user.info -e -t GRAYLOG-INSTALLER
    function_stopGraylogStack
    function_startGraylogStack
    function_checkSystemAvailability

    function_createInputs ${GRAYLOG_ADMIN_TOKEN}
    function_createEvaluationConfiguration ${GRAYLOG_ADMIN_TOKEN}
    function_enableIlluminatePackages ${GRAYLOG_ADMIN_TOKEN}    
    function_enableGraylogSidecar

    GRAYLOG_LICENSE_SECURITY=$(function_checkSecurityLicense ${GRAYLOG_ADMIN_TOKEN})
    function_configureSecurityFeatures ${GRAYLOG_ADMIN_TOKEN}
fi

echo "[INFO] - GRAYLOG INSTALLATION FINISHED" | logger -p user.info -e -t GRAYLOG-INSTALLER

exit
