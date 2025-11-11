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
INSTALL_LOG="./graylog-eval-installation.log"
SCRIPT_DEPENDENCIES="dnsutils net-tools vim git jq tcpdump pwgen acl htop unzip" 


###############################################################################
#
# Functions Definition

function_installScriptDependencies () {
    for PACKAGE in ${SCRIPT_DEPENDENCIES}
    do
        sudo apt-get -qq install ${PACKAGE} | logger -s
    done
}

function_checkSnapshot () {

    read -p "[INPUT] - Please confirm that you created a Snapshot of this VM before running this Script [yes/no]]: " SNAPSHOT_CREATED

    local SNAPSHOT_CREATED=${SNAPSHOT_CREATED:-yes}

    if [[ ${SNAPSHOT_CREATED} != "yes" ]]
    then
        echo "[ERROR] - User did not confirm a snapshot was created - exiting"
        sleep 5
        exit
    else
        echo "[INFO] - User confirmed a snapshot was created"
    fi 

    echo ${SNAPSHOT_CREATED}
}

function_defineAdminName () {

    while [[ ${VALID_ADMIN} != "true" ]]
    do
        read -p "[INPUT] - Please add the name of your central Administration User [admin]: " GRAYLOG_ADMIN
        
        local GRAYLOG_ADMIN=${GRAYLOG_ADMIN:-admin}
        local FORBIDDEN_USERNAMES=$(cat /etc/passwd | awk -F":" '{print $1}')
        
        if [[ ${GRAYLOG_ADMIN} =~ ^[A-Za-z0-9_-]{4,12}$ ]]
        then
            for USER_NAME in ${FORBIDDEN_USERNAMES}
            do
                if [[ ${GRAYLOG_ADMIN} == ${USER_NAME} ]]
                then                    
                    echo "[INFO] - A valid Username consists of 4-12 letters and MUST NOT be available on this system"
                    VALID_ADMIN="false"
                    break
                else
                    VALID_ADMIN="true"
                fi
            done
        fi
    done

    echo ${GRAYLOG_ADMIN}
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

    echo ${GRAYLOG_PASSWORD1}
} 

function_getSystemFqdn () {

    local LOCAL_IPS=$(ip a | grep -v inet6 | grep inet | awk -F" " '{print $2}' | cut -f1 -d "/")

    while [[ ${VALID_FQDN} != "true" ]]
    do    
        read -p "[INPUT] - Please add the fqdn of your Graylog Instance [eval.graylog.local]: " GRAYLOG_FQDN
        local GRAYLOG_FQDN=${GRAYLOG_FQDN:-eval.graylog.local}
        local FQDN_IP=$(nslookup ${GRAYLOG_FQDN} | grep -A3 answer | grep Address | awk -F":" '{print $2}')
        local SYSTEM_IP=$(ip a | grep -v inet6 | grep inet | awk -F" " '{print $2}' | cut -f1 -d "/")

        echo $FQDN_IP
        echo $SYSTEM_IP

        for IP in ${SYSTEM_IP}
        do
            echo "this is our ip: $IP"
            echo "this is our FQDN IP: $FQDN_IP"

            if [[ ${IP} == ${FQDN_IP} ]]
            then
                break
            fi
        done

        #VALID_FQDN="true"
    done

    echo $GRAYLOG_FQDN
}

#function_getProxySettings() {}

###############################################################################
#
# Dynamic Variables Definition

#SNAPSHOT_CREATED=$(function_checkSnapshot)
#GRAYLOG_PASSWORD=$(function_defineAdminPassword)
function_getSystemFqdn

# echo ${SNAPSHOT_CREATED}
#echo ${GRAYLOG_PASSWORD}

##
## 
## echo ${SNAPSHOT_CREATED} | logger -si "[INFO] - User confirmed snapshot was created" --priority user.warning
##
##
##