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
SYSTEM_PROXY=$(cat /etc/environment | grep http_proxy | cut -d "=" -f 2 | tr -d '"')



###############################################################################
#
# Functions Definition

function_checkSnapshot () {

    read -p "[INPUT] - Please confirm that you created a Snapshot of this VM before running this Script [yes/no]]: " SNAPSHOT_CREATED

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
        fi

        echo "[INFO] - A valid Username consists of 4-12 letters, try again"

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

function_checkInternetConnectivity () {

    local CONNECTIVITY_TEST=$(curl -ILs https://github.com --connect-timeout 7 | head -n1 )
    
    if [[ ${CONNECTIVITY_TEST} == "" ]]
    then
        echo "[INFO] - Internet Connection not available, please validate - exiting"
        exit
    fi
}

function_checkSystemRequirements () {



    
}

function_installScriptDependencies () {

    echo "[INFO] - Installing required packages: ${SCRIPT_DEPENDENCIES} "

    sudo apt -qq update -y 2>/dev/null >/dev/null 
    sudo apt -qq upgrade -y 2>/dev/null >/dev/null 
    sudo apt -qq autoremove -y 2>/dev/null >/dev/null

    sudo apt install ${SCRIPT_DEPENDENCIES} 2>/dev/null >/dev/null
}


###############################################################################
#
# Dynamic Variables Definition

#SNAPSHOT_CREATED=$(function_checkSnapshot)
#GRAYLOG_ADMIN=$(function_defineAdminName)
#GRAYLOG_PASSWORD=$(function_defineAdminPassword)
#GRAYLOG_FQDN=$(function_getSystemFqdn)
#GRAYLOG_PROXY=$(function_checkInternetConnectivity)

###############################################################################
#
# Graylog Installation

function_getSystemFqdn