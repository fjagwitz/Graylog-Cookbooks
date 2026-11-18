#!/bin/bash
#
# title:             GRAYLOG-INSTALLER
# description:       Installs a complete Graylog Cluster for testing purposes
# author:            Friedrich von Jagwitz
# email:             fvj@graylog.com
# date:              2026-11-11
# version:           7.2
# usage:             bash install-graylog.sh
# notes:             Must be saved to a file and run as a regular user with
#                    sudo rights (do not pipe it into bash). After the base
#                    installation it registers itself in /etc/cron.hourly and
#                    finishes the setup once the licenses are available.
#==============================================================================

set -o pipefail

###############################################################################
#
# Static Variables Definition

GRAYLOG_VERSION="7.2"
GRAYLOG_HOME="/opt"
GRAYLOG_PATH="${GRAYLOG_HOME}/graylog"
GRAYLOG_COMPOSE="docker-compose.yaml"
GRAYLOG_COMPOSE_FILE="${GRAYLOG_PATH}/${GRAYLOG_COMPOSE}"
GRAYLOG_STACK_ENV=".env"
GRAYLOG_SERVER_ENV="graylog.env"
GRAYLOG_DATANODE_ENV="datanode.env"
GRAYLOG_STATE_FILE="${GRAYLOG_PATH}/.installation"
GRAYLOG_TOKEN_FILE="${GRAYLOG_PATH}/.admintoken"
GRAYLOG_CREDENTIALS_FILE="${GRAYLOG_PATH}/your_graylog_credentials.txt"
GRAYLOG_RESET_SCRIPT="${GRAYLOG_PATH}/scripts/Reset-GraylogInstallation"
GRAYLOG_CRON_SCRIPT="/etc/cron.hourly/install-graylog"
GRAYLOG_REPOSITORY="https://github.com/fjagwitz/Graylog-Cookbooks.git"
GRAYLOG_ADMIN=""
GRAYLOG_PASSWORD=""
GRAYLOG_ADMIN_TOKEN=""
GRAYLOG_SIDECAR_TOKEN=""
GRAYLOG_FQDN=""
GRAYLOG_API="http://localhost/api"
GRAFANA_API="http://localhost/grafana/api"
GRAYLOG_SIDECAR="graylog-sidecar"
GRAYLOG_SIDECAR_TAG="sidecar-self-monitoring"
GRAYLOG_SIDECAR_REPO_DEB="graylog-sidecar-repository_1-5_all.deb"
GRAYLOG_SELF_MONITORING_STREAM_TITLE="Evaluation: Self-Monitoring Logs"
GRAYLOG_LICENSE_ENTERPRISE=""
GRAYLOG_LICENSE_SECURITY=""

# Proxy taken from the environment (https before http), normalised to a URL
SYSTEM_PROXY="${https_proxy:-${HTTPS_PROXY:-${http_proxy:-${HTTP_PROXY:-}}}}"
SYSTEM_PROXY="${SYSTEM_PROXY//\"/}"
if [[ -n ${SYSTEM_PROXY} && ${SYSTEM_PROXY} != http* ]]
then
    SYSTEM_PROXY="http://${SYSTEM_PROXY}"
fi

# Define minimum system requirements
SYSTEM_REQUIREMENTS_CPU="8"
SYSTEM_REQUIREMENTS_CPU_FLAGS="avx"
SYSTEM_REQUIREMENTS_MEMORY="32"
SYSTEM_REQUIREMENTS_OPT="900"
SYSTEM_REQUIREMENTS_VAR="300"
SYSTEM_REQUIREMENTS_OS="Ubuntu"

# Collector's Versions
GRAYLOG_COLLECTOR_VERSION="0.6.0"
GRAYLOG_SIDECAR_VERSION="1.5.6"
BEATS_COLLECTOR_VERSION="8.19.23"

# Define required dependencies to run the script as well as the Graylog Stack
SCRIPT_DEPENDENCIES="apt-utils bash-completion bind9-dnsutils btop ca-certificates curl cron dos2unix git iproute2 jq net-tools pwgen rsyslog tcpdump unzip vim"

# Retry behaviour for API wait loops: 30 attempts x 10s = 5 minutes max
RETRY_MAX_ATTEMPTS="30"
RETRY_INTERVAL="10"
# Waiting for the stack to come up: 60 x 20s = 20 minutes max
WAIT_SYSTEM_ATTEMPTS="60"
WAIT_SYSTEM_INTERVAL="20"
# Waiting for the preflight (initial setup) interface: 120 x 5s = 10 minutes max
WAIT_PREFLIGHT_ATTEMPTS="120"
WAIT_PREFLIGHT_INTERVAL="5"

# Runtime
LOG_TAG="GRAYLOG-INSTALLER"
LOG_FILE="${HOME:-/tmp}/graylog-installer.log"
LOCK_FILE="/run/lock/graylog-installer.lock"
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null)"
INSTALL_USER="$(id -un)"
INSTALL_GROUP="$(id -gn)"
INSTALL_PHASE=""
KEEPALIVE_PID=""
TMP_PATHS=()
GL_AUTH=""
GL_LAST_STATUS=""
GL_LAST_RESPONSE=""
GL_EXPECTED_STATUS=""
FAILED_ACTIONS=()

# Colours only on a terminal and only if NO_COLOR is not set (https://no-color.org)
if [[ -t 2 && -z ${NO_COLOR:-} ]]
then
    C_YELLOW=$'\e[1;33m'
    C_GREEN=$'\e[1;32m'
    C_RESET=$'\e[0m'
else
    C_YELLOW=""
    C_GREEN=""
    C_RESET=""
fi

###############################################################################
#
# Helper Functions (logging, error handling, API access)

_log () {
    local priority=${1} label=${2}
    shift 2
    logger -p "user.${priority}" -t "${LOG_TAG}" -- "[${label}] - $*" 2>/dev/null
    printf '%(%F %T)T [%s] - %s\n' -1 "${label}" "$*" >>"${LOG_FILE}" 2>/dev/null
    return 0
}
log_info ()  { _log info    INFO  "$@"; }
log_warn ()  { _log warning WARN  "$@"; }
log_error () { _log err     ERROR "$@"; }

# Console + syslog
warn () { printf '%s[WARN] - %s%s\n' "${C_YELLOW}" "$*" "${C_RESET}" >&2; log_warn "$@"; }
die ()  { echo "[ERROR] - $*" >&2; log_error "$@"; exit 1; }

# A non-fatal action failed: show it, log it and remember it for the final summary
fail () {
    warn "$@"
    FAILED_ACTIONS+=("$*")
}

# Green [INPUT] prompt text for 'read -p'
input_prompt () {
    printf '%s[INPUT] - %s%s' "${C_GREEN}" "$*" "${C_RESET}"
}

# run_step DESCRIPTION COMMAND [ARGS...]
#   Runs a non-fatal installation step. Records a failure if the step returns
#   non-zero without having reported a more specific error itself.
run_step () {
    local description=${1} failures_before=${#FAILED_ACTIONS[@]} rc
    shift

    log_info "STEP: ${description}"
    "$@"
    rc=$?

    if (( rc != 0 )) && (( ${#FAILED_ACTIONS[@]} == failures_before ))
    then
        fail "${description} FAILED (DETAILS: ${LOG_FILE})"
    elif (( ${#FAILED_ACTIONS[@]} > failures_before ))
    then
        log_warn "STEP COMPLETED WITH ERRORS: ${description}"
    fi

    return "${rc}"
}

# Summary of all failed actions, shown when the script ends
function_showFailureSummary () {
    local action

    if (( ${#FAILED_ACTIONS[@]} == 0 ))
    then
        return 0
    fi

    warn "${#FAILED_ACTIONS[@]} ACTION(S) FAILED - PLEASE REVIEW AND FIX THEM MANUALLY:"
    for action in "${FAILED_ACTIONS[@]}"
    do
        printf '%s         - %s%s\n' "${C_YELLOW}" "${action}" "${C_RESET}" >&2
        log_warn "  - ${action}"
    done
    warn "DETAILS: ${LOG_FILE} AND 'journalctl -t ${LOG_TAG}'"
}

# Progress output: console when interactive, syslog otherwise (cron)
progress () {
    if [[ -t 1 ]]; then echo "[INFO] - $*"; fi
    log_info "$@"
}

# Run a command, send its output to the log file instead of /dev/null
run_logged () {
    "$@" >>"${LOG_FILE}" 2>&1
}

apt_get () {
    local -a proxy_options=()
    if [[ -n ${SYSTEM_PROXY} ]]
    then
        proxy_options=(-o "Acquire::http::Proxy=${SYSTEM_PROXY}" -o "Acquire::https::Proxy=${SYSTEM_PROXY}")
    fi
    run_logged sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -q -y \
        -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
        -o DPkg::Lock::Timeout=300 "${proxy_options[@]}" "$@"
}

compose () {
    sudo docker compose -f "${GRAYLOG_COMPOSE_FILE}" "$@"
}

# download URL DESTINATION [MODE] - downloads as the current user (keeps proxy
# settings) and fails on HTTP errors. The file is installed with sudo only if the
# target folder is not writable by the current user, so temporary files stay
# owned by the user and can be cleaned up without root privileges.
download () {
    local url=${1} destination=${2} mode=${3:-0644} tmp_file
    local -a install_cmd=(install)

    if [[ ! -w $(dirname "${destination}") ]]
    then
        install_cmd=(sudo install)
    fi

    tmp_file=$(mktemp) || return 1
    if curl -fsSL --retry 5 --retry-delay 5 --retry-connrefused --connect-timeout 15 -o "${tmp_file}" "${url}" >>"${LOG_FILE}" 2>&1 \
        && "${install_cmd[@]}" -m "${mode}" "${tmp_file}" "${destination}" 2>>"${LOG_FILE}"
    then
        rm -f "${tmp_file}"
        return 0
    fi

    rm -f "${tmp_file}"
    log_error "DOWNLOAD FAILED: ${url}"
    return 1
}

# Escape a string for use in the replacement part of a sed s||| expression
sed_escape () {
    printf '%s' "${1}" | sed -e 's/[\\&|]/\\&/g'
}

# gl_api METHOD PATH_OR_URL [JSON]
#   Prints the response body; returns non-zero on connection or HTTP errors.
#   GL_LAST_STATUS / GL_LAST_RESPONSE hold status and body of the last call
#   (only visible to the caller when gl_api does not run in a subshell).
#   HTTP codes listed in GL_EXPECTED_STATUS (e.g. GL_EXPECTED_STATUS="400")
#   still return non-zero but are logged as INFO instead of ERROR.
#   Credentials come from GL_AUTH ("user:password" or "<token>:token") and are
#   passed through a file descriptor, so they never show up in the process list.
gl_api () {
    local method=${1} target=${2} data=${3-} url response status auth rc
    local -a curl_args

    if [[ ${target} == http* ]]; then url=${target}; else url="${GRAYLOG_API}${target}"; fi
    GL_LAST_STATUS=""
    GL_LAST_RESPONSE=""

    auth=${GL_AUTH}
    auth=${auth//\\/\\\\}
    auth=${auth//\"/\\\"}

    curl_args=(-sS --noproxy '*' --connect-timeout 10 --max-time 300 -X "${method}"
               -H "X-Requested-By: localhost" -H "Cache-Control: no-cache, no-store"
               -w '\n%{http_code}')
    if [[ -n ${data} ]]
    then
        curl_args+=(-H "Content-Type: application/json" --data-binary @-)
    fi

    if [[ -n ${auth} ]]
    then
        response=$(printf '%s' "${data}" | curl "${curl_args[@]}" -K <(printf 'user = "%s"\n' "${auth}") "${url}" 2>>"${LOG_FILE}")
        rc=$?
    else
        response=$(printf '%s' "${data}" | curl "${curl_args[@]}" "${url}" 2>>"${LOG_FILE}")
        rc=$?
    fi

    if (( rc != 0 )) || [[ -z ${response} ]]
    then
        GL_LAST_STATUS="000"
        log_error "API ${method} ${url%%\?*} - CONNECTION FAILED"
        return 1
    fi

    status=${response##*$'\n'}
    response=${response%$'\n'*}
    GL_LAST_STATUS=${status}
    GL_LAST_RESPONSE=${response}

    if [[ ${status} != 2?? ]]
    then
        if [[ " ${GL_EXPECTED_STATUS} " == *" ${status} "* ]]
        then
            log_info "API ${method} ${url%%\?*} - HTTP ${status} (EXPECTED): ${response:0:300}"
        else
            log_error "API ${method} ${url%%\?*} - HTTP ${status}: ${response:0:300}"
        fi
        return 1
    fi

    printf '%s' "${response}"
}

# gl_try DESCRIPTION METHOD PATH [JSON] - non-fatal configuration step
gl_try () {
    local description=${1}
    shift

    log_info "${description}"
    if ! gl_api "$@" >/dev/null
    then
        fail "${description} FAILED (HTTP ${GL_LAST_STATUS:-000}, DETAILS: ${LOG_FILE})"
        return 1
    fi
}

function_removeScript () {
    # The installer removes itself after use; a failure here is not fatal
    [[ -f ${SCRIPT_PATH} ]] || return 0
    rm -f -- "${SCRIPT_PATH}" 2>/dev/null \
        || sudo -n rm -f -- "${SCRIPT_PATH}" 2>/dev/null \
        || fail "COULD NOT REMOVE ${SCRIPT_PATH}, PLEASE DELETE IT MANUALLY"
}

function_writeState () {
    if ! echo "${1}" | sudo tee "${GRAYLOG_STATE_FILE}" >/dev/null
    then
        log_error "COULD NOT WRITE STATE '${1}' TO ${GRAYLOG_STATE_FILE}"
        return 1
    fi
    log_info "INSTALLATION STATE: ${1^^}"
}

function_onExit () {
    local exit_code=$? tmp_path

    if [[ -n ${KEEPALIVE_PID} ]]; then kill "${KEEPALIVE_PID}" 2>/dev/null; fi

    # Temporary files may have been touched by root (sudo); fall back to sudo without prompting
    for tmp_path in "${TMP_PATHS[@]}"
    do
        [[ -e ${tmp_path} ]] || continue
        rm -rf -- "${tmp_path}" 2>/dev/null \
            || sudo -n rm -rf -- "${tmp_path}" 2>/dev/null \
            || fail "COULD NOT REMOVE TEMPORARY PATH ${tmp_path}, PLEASE DELETE IT MANUALLY"
    done

    # Everything that failed along the way, in one list
    function_showFailureSummary

    if (( exit_code != 0 )) && [[ ${INSTALL_PHASE} == "install" ]]
    then
        echo "[ERROR] - THE INSTALLATION WAS ABORTED (EXIT CODE ${exit_code})" >&2
        echo "[ERROR] - DETAILS: ${LOG_FILE} AND 'journalctl -t ${LOG_TAG}'" >&2
        echo "[ERROR] - RUN THIS SCRIPT AGAIN TO REMOVE THE TRACES OF THE FAILED INSTALLATION, OR RESTORE YOUR SNAPSHOT" >&2
        log_error "INSTALLATION ABORTED WITH EXIT CODE ${exit_code}"
    fi
}

trap function_onExit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

###############################################################################
#
# Functions Definition

function_checkInstallUser () {

    if (( EUID == 0 ))
    then
        die "THIS SCRIPT CANNOT BE EXECUTED AS ROOT. EXIT."
    fi

    if [[ ! -f ${SCRIPT_PATH} ]]
    then
        die "THIS SCRIPT MUST BE SAVED TO A FILE AND STARTED WITH 'bash install-graylog.sh' (PIPING IT INTO BASH IS NOT SUPPORTED)"
    fi

    command -v sudo >/dev/null 2>&1 || die "SUDO IS REQUIRED TO RUN THIS SCRIPT"
    sudo -v || die "USER ${INSTALL_USER^^} NEEDS SUDO PRIVILEGES"

    log_info "RUNNING THIS SCRIPT AS USER ${INSTALL_USER^^}"
}

function_checkSnapshot () {
    local snapshot_created

    read -rp "$(input_prompt "Please confirm that you created a Snapshot of the VM before running this Script [no/yes]: ")" snapshot_created

    if [[ ${snapshot_created:-no} != "yes" ]]
    then
        die "NO SNAPSHOT WAS CREATED, PLEASE CREATE ONE - EXITING"
    fi
}

function_defineAdminName () {
    local admin_name

    while true
    do
        read -rp "$(input_prompt "Please add the name of your central Administration User [eval-admin]: ")" admin_name
        admin_name=${admin_name:-eval-admin}

        if [[ ! ${admin_name} =~ ^[A-Za-z0-9_-]{4,12}$ ]]
        then
            echo "[INFO] - A VALID USERNAME CONSISTS OF 4-12 CHARACTERS (LETTERS, DIGITS, _ OR -), TRY AGAIN"
        elif getent passwd "${admin_name}" >/dev/null
        then
            echo "[INFO] - A VALID USERNAME MUST NOT BE AVAILABLE ON THIS SYSTEM, TRY AGAIN"
        else
            break
        fi
    done

    # Set global Variable for Graylog Admin
    GRAYLOG_ADMIN=${admin_name}
}

function_defineAdminPassword () {
    local password_1 password_2

    while true
    do
        IFS= read -rsp "$(input_prompt "Please add the central Administration Password [MyP@ssw0rd]: ")" password_1
        echo
        password_1=${password_1:-MyP@ssw0rd}

        # The password is stored in the colon-separated Samba user file
        if [[ ${password_1} == *:* ]]
        then
            echo "[INFO] - THE PASSWORD MUST NOT CONTAIN A COLON (:), TRY AGAIN"
            continue
        fi

        IFS= read -rsp "$(input_prompt "Please confirm the central Administration Password: ")" password_2
        echo
        password_2=${password_2:-MyP@ssw0rd}

        if [[ ${password_1} == "${password_2}" ]]
        then
            break
        fi
        echo "[INFO] - THE PASSWORDS DO NOT MATCH, TRY AGAIN"
    done

    GRAYLOG_PASSWORD=${password_1}
}

function_getDnsServers () {
    # Prints the upstream DNS servers. On Ubuntu /etc/resolv.conf points to the local
    # systemd-resolved stub (127.0.0.53), which also answers from /etc/hosts - so the
    # real upstream servers are taken from /run/systemd/resolve/resolv.conf instead.
    local resolv_conf

    for resolv_conf in /run/systemd/resolve/resolv.conf /etc/resolv.conf
    do
        [[ -r ${resolv_conf} ]] || continue
        awk '$1 == "nameserver" && $2 !~ /^127\./ && $2 != "::1" {print $2}' "${resolv_conf}" | grep . && return 0
    done

    return 1
}

function_resolveFqdn () {
    # FQDN - prints the IPv4 addresses the FQDN has in DNS (as clients see it), without /etc/hosts
    local fqdn=${1} dns_server answer

    for dns_server in $(function_getDnsServers)
    do
        answer=$(dig +short +time=3 +tries=1 A "${fqdn}" "@${dns_server}" 2>/dev/null | grep -E '^[0-9]+(\.[0-9]+){3}$')
        if [[ -n ${answer} ]]
        then
            log_info "DNS SERVER ${dns_server} RESOLVES ${fqdn^^} TO: ${answer//$'\n'/, }"
            printf '%s\n' "${answer}"
            return 0
        fi
        log_info "DNS SERVER ${dns_server} HAS NO A RECORD FOR ${fqdn^^}"
    done

    return 1
}

function_getSystemFqdn () {
    local system_ips fqdn fqdn_ips local_answer ip valid_fqdn check_ignore
    local fqdn_regex='^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$'

    # Only addresses clients can reach (no loopback)
    system_ips=$(ip -o -4 addr show scope global 2>/dev/null | awk '{print $4}' | cut -d "/" -f1)
    if [[ -z ${system_ips} ]]
    then
        fail "COULD NOT DETERMINE THE IP ADDRESSES OF THIS SYSTEM"
    fi

    if ! function_getDnsServers >/dev/null
    then
        warn "NO UPSTREAM DNS SERVER CONFIGURED, THE FQDN CANNOT BE VALIDATED"
    fi

    while true
    do
        read -rp "$(input_prompt "Please add the fqdn of your Graylog Instance [eval.graylog.local]: ")" fqdn
        fqdn=${fqdn:-eval.graylog.local}
        fqdn=${fqdn,,}

        if [[ ! ${fqdn} =~ ${fqdn_regex} ]]
        then
            echo "[INFO] - \"${fqdn}\" IS NOT A VALID FQDN, TRY AGAIN"
            continue
        fi

        valid_fqdn="false"
        fqdn_ips=$(function_resolveFqdn "${fqdn}")

        for ip in ${fqdn_ips}
        do
            if grep -qxF "${ip}" <<<"${system_ips}"
            then
                valid_fqdn="true"
            fi
        done

        if [[ ${valid_fqdn} == "true" ]]
        then
            log_info "FQDN ${fqdn^^} RESOLVES TO THIS SYSTEM"
            break
        fi

        # Explain why the check failed
        if [[ -n ${fqdn_ips} ]]
        then
            warn "${fqdn^^} RESOLVES TO ${fqdn_ips//$'\n'/, } IN DNS, BUT THIS SYSTEM HAS ${system_ips//$'\n'/, }"
        else
            local_answer=$(getent ahostsv4 "${fqdn}" 2>/dev/null | awk 'NR==1 {print $1}')
            if [[ ${local_answer} == 127.* ]]
            then
                warn "${fqdn^^} HAS NO DNS RECORD; IT ONLY RESOLVES LOCALLY TO ${local_answer} (/etc/hosts), WHICH CLIENTS CANNOT USE"
            elif [[ -n ${local_answer} ]]
            then
                warn "${fqdn^^} HAS NO DNS RECORD; IT ONLY RESOLVES LOCALLY (/etc/hosts) TO ${local_answer}"
            else
                warn "${fqdn^^} CANNOT BE RESOLVED"
            fi
            warn "PLEASE CREATE A DNS A RECORD: ${fqdn} -> $(head -n 1 <<<"${system_ips}")"
        fi

        read -rp "$(input_prompt "The FQDN you provided does not resolve to an IP address of this system; continue anyway? [no/yes]: ")" check_ignore
        if [[ ${check_ignore:-no} == "yes" ]]
        then
            warn "CONTINUE WITHOUT VALIDATED FQDN, EXPECTING PRODUCT ISSUES"
            break
        fi
    done

    # Set global Variable for Graylog FQDN
    GRAYLOG_FQDN=${fqdn}
}

function_checkInternetConnectivity () {
    local http_status

    command -v curl >/dev/null 2>&1 || die "CURL IS REQUIRED TO RUN THIS SCRIPT (sudo apt-get install curl)"

    http_status=$(curl -sS -o /dev/null -L --connect-timeout 7 --max-time 30 -w '%{http_code}' https://github.com 2>>"${LOG_FILE}")

    if [[ ${http_status} != "200" ]]
    then
        die "INTERNET CONNECTION NOT AVAILABLE (HTTP STATUS: ${http_status:-NONE}). EXIT."
    fi

    log_info "INTERNET CONNECTION SUCCESSFULLY ESTABLISHED"
}

function_checkPatchLevel () {
    local seconds

    log_info "DOWNLOAD AND INSTALL LATEST UPDATES"
    apt_get update  || die "PACKAGE LIST UPDATE FAILED (DETAILS: ${LOG_FILE})"
    apt_get upgrade || die "SYSTEM UPGRADE FAILED (DETAILS: ${LOG_FILE})"

    if [[ -f /var/run/reboot-required ]]
    then
        echo "[INFO] - THIS SYSTEM NEEDS A REBOOT BEFORE THE INSTALLATION "
        echo "[INFO] - DOWNLOAD THE INSTALLATION SCRIPT AGAIN AND RESTART THE INSTALLATION PROCESS AFTER REBOOT "

        for (( seconds = 10; seconds > 0; seconds-- ))
        do
            echo -e "[INFO] - \e[4;33mREBOOT IN ${seconds} SECONDS\e[0m (PRESS CTRL+C TO INTERRUPT)"
            sleep 1
        done

        log_info "SYSTEM REBOOT AFTER UPDATE INSTALLATION"
        function_removeScript
        sudo reboot
        exit 0
    fi
}

function_freeSpaceGb () {
    local space
    space=$(df -BG --output=avail "${1}" 2>/dev/null | tail -n 1 | tr -dc '0-9')
    echo "${space:-0}"
}

function_checkSystemRequirements () {
    local os_id os_name memory cpu_cores opt_space var_space flag connectivity_type
    local -a missing_flags=() errors=()

    os_id=$(. /etc/os-release 2>/dev/null && echo "${ID:-}")
    os_name=$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}")
    memory=$(awk '/^MemTotal:/ {print int($2/1024/1024)+1}' /proc/meminfo)
    cpu_cores=$(nproc)
    opt_space=$(function_freeSpaceGb /opt)
    var_space=$(function_freeSpaceGb /var)

    for flag in ${SYSTEM_REQUIREMENTS_CPU_FLAGS}
    do
        grep -qwi -- "${flag}" /proc/cpuinfo || missing_flags+=("${flag}")
    done

    if [[ -z ${SYSTEM_PROXY} ]]
    then
        connectivity_type="Direct (without Proxy)"
    else
        connectivity_type="Proxied: ${SYSTEM_PROXY}"
        log_info "SET SYSTEM PROXY TO ${SYSTEM_PROXY}"
    fi

    [[ ${os_id,,} == "${SYSTEM_REQUIREMENTS_OS,,}" ]] \
        || errors+=("OPERATING SYSTEM MUST BE ${SYSTEM_REQUIREMENTS_OS^^}, BUT IS ${os_name}")
    (( memory >= SYSTEM_REQUIREMENTS_MEMORY )) \
        || errors+=("MEMORY MUST BE AT LEAST ${SYSTEM_REQUIREMENTS_MEMORY} GB, BUT IS ONLY ${memory} GB")
    (( cpu_cores >= SYSTEM_REQUIREMENTS_CPU )) \
        || errors+=("THE SYSTEM MUST HAVE AT LEAST ${SYSTEM_REQUIREMENTS_CPU} VCPU CORES, BUT HAS ONLY ${cpu_cores}")
    (( ${#missing_flags[@]} == 0 )) \
        || errors+=("THE CPU MUST SUPPORT THE ${missing_flags[*]^^} FLAG(S), BUT DOES NOT")
    (( opt_space >= SYSTEM_REQUIREMENTS_OPT )) \
        || errors+=("THE /opt FOLDER MUST PROVIDE AT LEAST ${SYSTEM_REQUIREMENTS_OPT} GB STORAGE, BUT HAS ONLY ${opt_space} GB")
    (( var_space >= SYSTEM_REQUIREMENTS_VAR )) \
        || errors+=("THE /var/lib/docker FOLDER MUST PROVIDE AT LEAST ${SYSTEM_REQUIREMENTS_VAR} GB STORAGE, BUT HAS ONLY ${var_space} GB")

    if (( ${#errors[@]} > 0 ))
    then
        printf '[ERROR] - %s\n' "${errors[@]}" >&2
        die "SYSTEM REQUIREMENTS NOT MET. EXIT."
    fi

    echo "[INFO] - SYSTEM REQUIREMENTS CHECK SUCCESSFUL:

         Operating System:  ${os_name}
         Storage (/opt)  :  ${opt_space} GB
         Storage (/var)  :  ${var_space} GB
         Memory          :  ${memory} GB
         CPU Cores       :  ${cpu_cores} vCPU
         CPU Flags       :  ${SYSTEM_REQUIREMENTS_CPU_FLAGS^^} available
         Internet        :  ${connectivity_type}
        "

    if [[ $(df --output=target /opt | tail -n 1) == "$(df --output=target /var | tail -n 1)" ]] \
        && (( opt_space < SYSTEM_REQUIREMENTS_OPT + SYSTEM_REQUIREMENTS_VAR ))
    then
        warn "/opt AND /var SHARE ONE FILESYSTEM WITH ${opt_space} GB FREE; BOTH TOGETHER NEED $(( SYSTEM_REQUIREMENTS_OPT + SYSTEM_REQUIREMENTS_VAR )) GB"
    fi
}

function_installScriptDependencies () {

    # The package lists were refreshed by function_checkPatchLevel
    log_info "CLEAN UP EVALUATION SYSTEM"
    apt_get autoremove || fail "APT AUTOREMOVE FAILED"

    log_info "ADD SYSTEM REQUIREMENTS"
    # shellcheck disable=SC2086 # word splitting intended
    apt_get install ${SCRIPT_DEPENDENCIES} || die "INSTALLATION OF SCRIPT DEPENDENCIES FAILED (DETAILS: ${LOG_FILE})"

    if getent group tcpdump >/dev/null
    then
        log_info "ADD ${INSTALL_USER^^} TO TCPDUMP GROUP"
        sudo usermod -aG tcpdump "${INSTALL_USER}" || fail "COULD NOT ADD ${INSTALL_USER^^} TO TCPDUMP GROUP"
    fi
}

# following https://docs.docker.com/engine/install/ubuntu
function_installDocker () {
    local docker_os_packages="docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc"
    local docker_ce_packages="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
    local docker_url="https://download.docker.com/linux/ubuntu"
    local docker_key="/etc/apt/keyrings/docker.asc"
    local docker_proxy_conf="/etc/systemd/system/docker.service.d/http-proxy.conf"
    local installed_packages codename architecture

    if ! command -v docker >/dev/null 2>&1
    then
        log_info "REMOVE DOCKER LEFTOVERS"
        # shellcheck disable=SC2086 # word splitting intended
        installed_packages=$(dpkg-query -W -f='${Package} ${Status}\n' ${docker_os_packages} 2>/dev/null | awk '/ installed$/ {print $1}')
        if [[ -n ${installed_packages} ]]
        then
            # shellcheck disable=SC2086
            apt_get remove ${installed_packages} || die "COULD NOT REMOVE CONFLICTING PACKAGES: ${installed_packages}"
        fi

        log_info "ADD DOCKER REPOSITORY"
        sudo install -m 0755 -d /etc/apt/keyrings || die "COULD NOT CREATE /etc/apt/keyrings"
        download "${docker_url}/gpg" "${docker_key}" 0644 || die "COULD NOT DOWNLOAD THE DOCKER REPOSITORY KEY"

        architecture=$(dpkg --print-architecture)
        codename=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME}}")
        echo "deb [arch=${architecture} signed-by=${docker_key}] ${docker_url} ${codename} stable" \
            | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null || die "COULD NOT ADD THE DOCKER REPOSITORY"

        apt_get update || die "PACKAGE LIST UPDATE FAILED (DETAILS: ${LOG_FILE})"

        log_info "INSTALL DOCKER PACKAGES: ${docker_ce_packages^^}"
        # shellcheck disable=SC2086 # word splitting intended
        apt_get install ${docker_ce_packages} || die "DOCKER INSTALLATION FAILED (DETAILS: ${LOG_FILE})"
    fi

    sudo docker compose version >/dev/null 2>&1 || die "THE DOCKER COMPOSE PLUGIN IS NOT AVAILABLE"

    # https://docs.docker.com/engine/daemon/proxy/
    if [[ -n ${SYSTEM_PROXY} ]]
    then
        log_info "CONFIGURE PROXY FOR DOCKER DAEMON"
        sudo install -m 0755 -d "$(dirname "${docker_proxy_conf}")" || die "COULD NOT CREATE DOCKER SERVICE DROP-IN FOLDER"
        printf '[Service]\nEnvironment="HTTP_PROXY=%s" "HTTPS_PROXY=%s" "NO_PROXY=localhost,127.0.0.1,::1"\n' "${SYSTEM_PROXY}" "${SYSTEM_PROXY}" \
            | sudo tee "${docker_proxy_conf}" >/dev/null || die "COULD NOT CONFIGURE PROXY FOR DOCKER"
    fi

    log_info "ADD ${INSTALL_USER^^} TO DOCKER GROUP"
    sudo usermod -aG docker "${INSTALL_USER}" || fail "COULD NOT ADD ${INSTALL_USER^^} TO DOCKER GROUP"

    log_info "RESTART DOCKER SERVICE"
    { sudo systemctl daemon-reload && sudo systemctl enable docker.service && sudo systemctl restart docker.service; } >>"${LOG_FILE}" 2>&1 \
        || die "DOCKER SERVICE COULD NOT BE STARTED"
}

# following https://go2docs.graylog.org/current/getting_in_log_data/set_up_sidecar_collectors.htm
function_installGraylogSidecarOnEvaluationHost () {
    local sidecar_token=${1}
    local sidecar_yaml="/etc/graylog/sidecar/sidecar.yml"
    local repo_dir repo_deb

    if dpkg-query -W -f='${Status}' graylog-sidecar 2>/dev/null | grep -q "install ok installed"
    then
        log_info "GRAYLOG SIDECAR ALREADY INSTALLED, SKIPPING"
        return 0
    fi

    log_info "ADD GRAYLOG SIDECAR REPOSITORY"
    repo_dir=$(mktemp -d) || return 1
    TMP_PATHS+=("${repo_dir}")
    repo_deb="${repo_dir}/${GRAYLOG_SIDECAR_REPO_DEB}"
    download "https://packages.graylog2.org/repo/packages/${GRAYLOG_SIDECAR_REPO_DEB}" "${repo_deb}" 0644 || return 1
    run_logged sudo dpkg -i "${repo_deb}" || return 1

    log_info "INSTALL GRAYLOG SIDECAR"
    apt_get update || return 1
    apt_get install graylog-sidecar || return 1

    log_info "CONFIGURE GRAYLOG SIDECAR ON HOST"
    # Keep the original configuration once. An explicit check instead of 'cp -n' / '--update=none':
    # coreutils >= 9.2 warns about -n, and coreutils < 9.3 (Ubuntu 22.04) has no --update=none.
    if ! sudo test -f "${sidecar_yaml}"
    then
        log_error "${sidecar_yaml} NOT FOUND AFTER SIDECAR INSTALLATION"
        return 1
    fi
    if ! sudo test -e "${sidecar_yaml}.bak"
    then
        sudo cp -p "${sidecar_yaml}" "${sidecar_yaml}.bak" || fail "COULD NOT BACK UP ${sidecar_yaml}"
    fi
    # Works whether the keys are commented out or not; only the first match of each key is changed
    sudo sed -E -i \
        -e "0,/^#?[[:space:]]*server_url:/ s|^#?[[:space:]]*server_url:.*|server_url: \"$(sed_escape "${GRAYLOG_API}")/\"|" \
        -e "0,/^#?[[:space:]]*server_api_token:/ s|^#?[[:space:]]*server_api_token:.*|server_api_token: \"${sidecar_token}\"|" \
        -e "/^[[:space:]]*-[[:space:]]*default[[:space:]]*$/d" \
        -e "0,/^#?[[:space:]]*tags:/ s|^#?[[:space:]]*tags:.*|tags: [\"${GRAYLOG_SIDECAR_TAG}\"]|" \
        "${sidecar_yaml}" || return 1

    if ! sudo grep -qF "server_api_token: \"${sidecar_token}\"" "${sidecar_yaml}"
    then
        log_error "SIDECAR TOKEN COULD NOT BE WRITTEN TO ${sidecar_yaml}"
        return 1
    fi
}

function_setEnvValue () {
    # FILE KEY VALUE - replaces 'KEY = ""' with 'KEY = "VALUE"'
    local file=${1} key=${2} value=${3}

    sudo sed -i "s|${key} = \"\"|${key} = \"$(sed_escape "${value}")\"|g" "${file}" || return 1
    if ! sudo grep -qF "${key} = \"${value}\"" "${file}"
    then
        fail "COULD NOT SET ${key} IN ${file}"
        return 1
    fi
}

function_installGraylogStack () {
    local install_path folder
    local folders_with_graylog_permissions="archives certs datalake notifications"
    local shared_folders="lookuptables sources"
    local graylog_env="${GRAYLOG_PATH}/${GRAYLOG_SERVER_ENV}"
    local datanode_env="${GRAYLOG_PATH}/${GRAYLOG_DATANODE_ENV}"
    local stack_env="${GRAYLOG_PATH}/${GRAYLOG_STACK_ENV}"
    local system_password_secret system_root_password_sha2
    local -a items

    install_path=$(mktemp -d) || die "COULD NOT CREATE A TEMPORARY FOLDER"
    TMP_PATHS+=("${install_path}")

    # Stop and disable ttyS0 Service
    log_info "STOP AND DISABLE SERVICE FOR TTYS0 TO AVOID UNNECESSARY LOGS"
    if systemctl list-unit-files 'serial-getty@.service' >/dev/null 2>&1
    then
        run_logged sudo systemctl stop serial-getty@ttyS0.service \
            || log_info "SERIAL-GETTY@TTYS0 WAS NOT RUNNING"
        run_logged sudo systemctl mask serial-getty@ttyS0.service \
            || fail "COULD NOT DISABLE SERIAL-GETTY@TTYS0 (MAY CAUSE ADDITIONAL LOG MESSAGES)"
    fi

    # Configure vm.max_map_count for Opensearch (https://docs.opensearch.org/2.19/install-and-configure/install-opensearch/index)
    log_info "CONFIGURE FILESYSTEM FOR OPENSEARCH"
    echo "vm.max_map_count=262144" | sudo tee /etc/sysctl.d/99-opensearch.conf >/dev/null || die "COULD NOT WRITE /etc/sysctl.d/99-opensearch.conf"
    run_logged sudo sysctl -p /etc/sysctl.d/99-opensearch.conf || die "COULD NOT APPLY vm.max_map_count"

    # Create required Folders in the Filesystem
    log_info "CREATE REQUIRED SUBFOLDERS IN /OPT"
    sudo mkdir -p "${GRAYLOG_PATH}"/{archives,assetdata,backup,certs/{root_ca,input_tls},contentpacks,database/{datanode1,datanode2,datanode3,datanode9,warm_tier},datalake,logsamples,lookuptables,maxmind,nessus/ssl,nginx1,nginx2,notifications,prometheus,samba,scripts,sources/{Graylog_Collector,Graylog_Sidecar,Filebeat_Standalone,Winlogbeat_Standalone,NXLog_CommunityEdition}} \
        || die "COULD NOT CREATE THE FOLDER STRUCTURE IN ${GRAYLOG_PATH}"

    log_info "CLONE GITHUB REPO"
    run_logged git clone -q --depth 1 --single-branch --branch "Graylog-${GRAYLOG_VERSION}" "${GRAYLOG_REPOSITORY}" "${install_path}" \
        || die "COULD NOT CLONE ${GRAYLOG_REPOSITORY} (BRANCH Graylog-${GRAYLOG_VERSION})"

    log_info "COPY CLONED CONTENT TO FOLDERS"
    shopt -s nullglob
    items=("${install_path}/01_Installation/compose/"*)
    shopt -u nullglob
    (( ${#items[@]} > 0 )) || die "THE CLONED REPOSITORY DOES NOT CONTAIN 01_Installation/compose"
    sudo cp -R "${items[@]}" "${GRAYLOG_PATH}/" || die "COULD NOT COPY THE STACK FILES TO ${GRAYLOG_PATH}"
    [[ -f ${GRAYLOG_COMPOSE_FILE} ]] || die "${GRAYLOG_COMPOSE_FILE} NOT FOUND"

    # Reformat all Windows files to DOS format
    log_info "REFORMAT WINDOWS FILES TO DOS CRLF"
    sudo find "${GRAYLOG_PATH}/sources" "${GRAYLOG_PATH}/lookuptables" -type f -exec unix2dos -q -- {} + >>"${LOG_FILE}" 2>&1 \
        || fail "SOME FILES COULD NOT BE CONVERTED TO CRLF"

    # Adapting Permissions for proper access by the Datanode Containers (999:999)
    log_info "SET PERMISSIONS FOR UID/GID 999 (DATANODE)"
    sudo chown -R 999:999 "${GRAYLOG_PATH}/database" || die "COULD NOT SET PERMISSIONS ON ${GRAYLOG_PATH}/database"

    # Adapting Permissions for proper access by the Graylog Containers (1100:1100)
    log_info "SET PERMISSIONS FOR UID/GID 1100 (GRAYLOG)"
    for folder in ${folders_with_graylog_permissions}
    do
        sudo chown -R 1100:1100 "${GRAYLOG_PATH}/${folder}" || die "COULD NOT SET PERMISSIONS ON ${GRAYLOG_PATH}/${folder}"
    done

    # Initially populate .env-file for the Stack
    log_info "SYSTEM VERSION IS ${GRAYLOG_VERSION^^}"
    log_info "SYSTEM FQDN IS ${GRAYLOG_FQDN^^}"
    printf 'GRAYLOG_VERSION = "%s"\nGRAYLOG_FQDN = "%s"\n' "${GRAYLOG_VERSION}" "${GRAYLOG_FQDN}" \
        | sudo tee -a "${stack_env}" >/dev/null || die "COULD NOT WRITE ${stack_env}"

    log_info "RENAME GRAYLOG ENVIRONMENT FILE"
    sudo mv "${GRAYLOG_PATH}/graylog.example" "${graylog_env}"   || die "${GRAYLOG_PATH}/graylog.example NOT FOUND"
    sudo mv "${GRAYLOG_PATH}/datanode.example" "${datanode_env}" || die "${GRAYLOG_PATH}/datanode.example NOT FOUND"

    log_info "POPULATE ENVIRONMENT FILE FOR GRAYLOG"
    system_password_secret=$(pwgen -N 1 -s 96) || die "COULD NOT GENERATE THE PASSWORD SECRET"
    system_root_password_sha2=$(printf '%s' "${GRAYLOG_PASSWORD}" | sha256sum | cut -d " " -f1)

    function_setEnvValue "${graylog_env}" GRAYLOG_ROOT_USERNAME "${GRAYLOG_ADMIN}"                       || die "COULD NOT CONFIGURE ${graylog_env}"
    function_setEnvValue "${graylog_env}" GRAYLOG_ROOT_PASSWORD_SHA2 "${system_root_password_sha2}"      || die "COULD NOT CONFIGURE ${graylog_env}"
    function_setEnvValue "${graylog_env}" GRAYLOG_PASSWORD_SECRET "${system_password_secret}"            || die "COULD NOT CONFIGURE ${graylog_env}"
    # setEnvValue reports failures itself; these two settings are not fatal
    function_setEnvValue "${graylog_env}" GRAYLOG_HTTP_EXTERNAL_URI "https://${GRAYLOG_FQDN}/"
    function_setEnvValue "${graylog_env}" GRAYLOG_TRANSPORT_EMAIL_WEB_INTERFACE_URL "https://${GRAYLOG_FQDN}"
    function_setEnvValue "${datanode_env}" GRAYLOG_DATANODE_PASSWORD_SECRET "${system_password_secret}"  || die "COULD NOT CONFIGURE ${datanode_env}"

    # set system proxy for Graylog
    if [[ -n ${SYSTEM_PROXY} ]]
    then
        sudo sed -i \
            -e "s|# GRAYLOG_HTTP_PROXY_URI = \"\"|GRAYLOG_HTTP_PROXY_URI = \"$(sed_escape "${SYSTEM_PROXY}")\"|g" \
            -e "s|# GRAYLOG_HTTP_NON_PROXY_HOSTS|GRAYLOG_HTTP_NON_PROXY_HOSTS|g" \
            "${graylog_env}" || fail "COULD NOT CONFIGURE THE PROXY IN ${graylog_env}"
    fi

    sudo sed -i "s|GF_SERVER_ROOT_URL: \"https://eval.graylog.local/grafana\"|GF_SERVER_ROOT_URL: \"https://${GRAYLOG_FQDN}/grafana\"|g" "${GRAYLOG_COMPOSE_FILE}" \
        || fail "COULD NOT SET THE GRAFANA ROOT URL"

    log_info "CONFIGURE SAMBA CONTAINER"
    for folder in ${shared_folders}
    do
        if ! sudo chmod -R 755 "${GRAYLOG_PATH}/${folder}" \
            || ! sudo find "${GRAYLOG_PATH}/${folder}" -type f -exec chmod 644 {} +
        then
            fail "COULD NOT SET PERMISSIONS ON ${GRAYLOG_PATH}/${folder} (SMB SHARE MAY NOT BE READABLE)"
        fi
    done

    echo "${GRAYLOG_ADMIN}:1000:siem:1000:${GRAYLOG_PASSWORD}" | sudo tee -a "${GRAYLOG_PATH}/samba/users.conf" >/dev/null \
        || die "COULD NOT WRITE ${GRAYLOG_PATH}/samba/users.conf"

    log_info "SET PERMISSIONS FOR HELPER SCRIPTS"
    sudo find "${GRAYLOG_PATH}/scripts" -maxdepth 1 -type f -exec chmod +x {} + || fail "COULD NOT MAKE THE HELPER SCRIPTS EXECUTABLE"

    # Pull only now: compose needs the populated .env and env files
    log_info "PULL CONTAINERS FOR GRAYLOG STACK"
    run_logged compose pull --quiet || die "PULLING THE CONTAINER IMAGES FAILED (DETAILS: ${LOG_FILE})"

    log_info "REMOVE INSTALLATION FOLDER ${install_path^^}"
    rm -rf -- "${install_path}" 2>/dev/null \
        || log_warn "COULD NOT REMOVE ${install_path} NOW, IT WILL BE REMOVED WHEN THE SCRIPT ENDS"
}

function_addScriptRepositoryToPathVariable () {
    local script_folder="${GRAYLOG_PATH}/scripts"
    local marker="# graylog-installer: helper scripts"

    if sudo grep -qF "${marker}" /etc/bash.bashrc
    then
        log_info "PATH VARIABLE IN /ETC/BASH.BASHRC DOES ALREADY CONTAIN SCRIPT FOLDER"
        return 0
    fi

    log_info "ADD SCRIPT FOLDER TO PATH VARIABLE AND SET CASE-INSENSITIVE AUTOCOMPLETION IN /ETC/BASH.BASHRC"
    # shellcheck disable=SC2016 # $PATH must be written literally
    printf '\n%s\nexport PATH="$PATH:%s"\nbind "set completion-ignore-case on"\n' "${marker}" "${script_folder}" \
        | sudo tee -a /etc/bash.bashrc >/dev/null || fail "COULD NOT UPDATE /etc/bash.bashrc"
}

function_enableGeoIpLocation () {
    local maxmind_db_types="ASN City Country"
    local maxmind_url="https://github.com/P3TERX/GeoLite.mmdb/raw/download"
    local geoip_config_path="/system/cluster_config/org.graylog.plugins.map.config.GeoIpResolverConfig"
    local geoip_config='{ "enabled":true,"enforce_graylog_schema":true,"db_vendor_type":"MAXMIND","city_db_path":"/etc/graylog/server/mmdb/GeoLite2-City.mmdb","asn_db_path":"/etc/graylog/server/mmdb/GeoLite2-ASN.mmdb","refresh_interval_unit":"DAYS","refresh_interval":14,"use_s3":false }'
    local geoip_enabled="" attempt db_type

    # Step 1: download each database once; curl retries transient network errors itself
    for db_type in ${maxmind_db_types}
    do
        log_info "DOWNLOAD MAXMIND DATABASE (${db_type^^})"
        if ! download "${maxmind_url}/GeoLite2-${db_type}.mmdb" "${GRAYLOG_PATH}/maxmind/GeoLite2-${db_type}.mmdb" 0644
        then
            fail "DOWNLOAD OF MAXMIND DATABASE (${db_type^^}) FAILED, SKIPPING GEOIP ACTIVATION"
            return 1
        fi
    done

    # Step 2: retry only the activation until Graylog reports it as enabled
    for (( attempt = 1; attempt <= RETRY_MAX_ATTEMPTS; attempt++ ))
    do
        log_info "ACTIVATE GEOIP PLUGIN (ATTEMPT ${attempt}/${RETRY_MAX_ATTEMPTS})"
        gl_api PUT "${geoip_config_path}" "${geoip_config}" >/dev/null \
            || log_warn "GEOIP CONFIGURATION ATTEMPT ${attempt} FAILED (HTTP ${GL_LAST_STATUS})"
        geoip_enabled=$(gl_api GET "${geoip_config_path}" | jq -r '.enabled' 2>/dev/null)

        if [[ ${geoip_enabled} == "true" ]]
        then
            log_info "GEOIP PLUGIN ACTIVATED"
            return 0
        fi
        sleep "${RETRY_INTERVAL}"
    done

    fail "GEOIP PLUGIN NOT ENABLED AFTER ${RETRY_MAX_ATTEMPTS} ATTEMPTS"
    return 1
}

function_downloadGraylogSidecarBinaries () {
    local target="${GRAYLOG_PATH}/sources/Graylog_Sidecar"
    local sidecar_msi="graylog-sidecar-${GRAYLOG_SIDECAR_VERSION}-1.msi"
    local sidecar_yml="sidecar-windows-msi-example.yml.template"

    log_info "DOWNLOAD GRAYLOG SIDECAR FOR WINDOWS"
    download "https://github.com/Graylog2/collector-sidecar/releases/download/${GRAYLOG_SIDECAR_VERSION}/${sidecar_msi}" "${target}/${sidecar_msi}" \
        && download "https://raw.githubusercontent.com/Graylog2/collector-sidecar/refs/heads/master/${sidecar_yml}" "${target}/${sidecar_yml}" \
        || { fail "DOWNLOAD OF GRAYLOG SIDECAR FOR WINDOWS FAILED"; return 1; }
}

function_downloadGraylogCollectorBinaries () {
    local collector_msi="graylog-collector-${GRAYLOG_COLLECTOR_VERSION}.msi"

    log_info "DOWNLOAD GRAYLOG COLLECTOR FOR WINDOWS"
    download "https://github.com/Graylog2/collector/releases/download/${GRAYLOG_COLLECTOR_VERSION}/${collector_msi}" \
        "${GRAYLOG_PATH}/sources/Graylog_Collector/${collector_msi}" \
        || { fail "DOWNLOAD OF GRAYLOG COLLECTOR FOR WINDOWS FAILED"; return 1; }
}

function_downloadBeatsBinaries () {
    local beat target package result=0

    for beat in filebeat winlogbeat
    do
        target="${GRAYLOG_PATH}/sources/${beat^}_Standalone"
        package="${beat}-${BEATS_COLLECTOR_VERSION}-windows-x86_64"

        log_info "DOWNLOAD ${beat^^} STANDALONE FOR WINDOWS"
        if download "https://artifacts.elastic.co/downloads/beats/${beat}/${package}.zip" "${target}/${package}.zip" \
            && download "https://artifacts.elastic.co/downloads/beats/${beat}/${package}.msi" "${target}/${package}.msi" \
            && run_logged sudo unzip -joq "${target}/${package}.zip" "*/${beat}.exe" -d "${target}" \
            && sudo cp "${target}/${beat}.exe" "${GRAYLOG_PATH}/sources/Graylog_Sidecar/"
        then
            sudo rm -f "${target}/${package}.zip" || fail "COULD NOT REMOVE ${target}/${package}.zip"
        else
            fail "DOWNLOAD OF ${beat^^} STANDALONE FOR WINDOWS FAILED"
            result=1
        fi
    done

    return "${result}"
}

function_downloadNxlogBinaries () {

    log_info "PREPARE NXLOG COMMUNITY EDITION FOR WINDOWS README FILE"
    printf '%s\n' \
        "DOWNLOAD LOCATION: https://nxlog.co/downloads/nxlog-ce#nxlog-community-edition" \
        "INTEGRATION INSTRUCTIONS: https://docs.nxlog.co/integrate/graylog.html" \
        | sudo tee "${GRAYLOG_PATH}/sources/NXLog_CommunityEdition/README.txt" >/dev/null \
        || fail "COULD NOT WRITE THE NXLOG README FILE"
}

function_prepareSidecarConfiguration () {
    local sidecar_token=${1}
    local sidecar_template="${GRAYLOG_PATH}/sources/Graylog_Sidecar/sidecar-windows-msi-example.yml.template"
    local sidecar_yml="${GRAYLOG_PATH}/sources/Graylog_Sidecar/sidecar.yml"

    log_info "CONFIGURE GRAYLOG SIDECAR FOR WINDOWS (MSI)"
    if [[ ! -f ${sidecar_template} ]]
    then
        fail "SIDECAR TEMPLATE NOT FOUND, SKIPPING WINDOWS SIDECAR CONFIGURATION"
        return 1
    fi

    sudo cp "${sidecar_template}" "${sidecar_yml}" || return 1

    # Graylog host URL, Sidecar token, node-id path, no TLS validation, evaluation tags
    sudo sed -i \
        -e "s|server_url: \"http://127.0.0.1:9000/api/\"|server_url: \"https://${GRAYLOG_FQDN}/api/\"|g" \
        -e "s|server_api_token: \"\"|server_api_token: \"${sidecar_token}\"|g" \
        -e "s|%%BRAND_VENDOR_NAME%%|Graylog|g" \
        -e "s|tls_skip_verify: false|tls_skip_verify: true|g" \
        -e 's/tags: \[\]/tags:\n  - evaluation\n  - windows\n  - applocker\n  - powershell\n  - defender\n  - rds\n  - forwarded\n  - ssh\n  - bpa\n  - bits\n  #- sysmon # Sysmon from Sysinternals\n  #- nxlog # Use nxlog instead of Beats\n  #- adds # Active Directory Domain Controller\n  #- dns # Domain Name Server/g' \
        "${sidecar_yml}" || { fail "COULD NOT CONFIGURE ${sidecar_yml}"; return 1; }

    # Change LF to CRLF as this is a Windows Configuration File
    run_logged sudo unix2dos "${sidecar_yml}" || fail "COULD NOT CONVERT ${sidecar_yml} TO CRLF"
}

function_checkSystemAvailability () {
    local attempt

    for (( attempt = 1; attempt <= WAIT_SYSTEM_ATTEMPTS; attempt++ ))
    do
        if [[ $(curl -s --noproxy '*' --max-time 10 "${GRAYLOG_API}/system/lbstatus" 2>/dev/null) == "ALIVE" ]]
        then
            return 0
        fi
        progress "WAIT FOR THE SYSTEM TO COME UP (${attempt}/${WAIT_SYSTEM_ATTEMPTS})"
        sleep "${WAIT_SYSTEM_INTERVAL}"
    done

    log_error "GRAYLOG DID NOT BECOME AVAILABLE WITHIN $(( WAIT_SYSTEM_ATTEMPTS * WAIT_SYSTEM_INTERVAL / 60 )) MINUTES"
    return 1
}

function_addDataNodesToCluster () {
    local credentials="" attempt finish_result
    local GL_AUTH

    log_info "WAIT FOR GRAYLOG TO BECOME CONFIGURABLE"

    # The preflight interface logs "Try clicking on http://<user>:<password>@..."
    for (( attempt = 1; attempt <= WAIT_PREFLIGHT_ATTEMPTS; attempt++ ))
    do
        credentials=$(compose logs --no-color graylog1 2>/dev/null | grep -oP 'clicking on https?://\K[^@\s]+(?=@)' | tail -n 1)
        [[ -n ${credentials} ]] && break
        sleep "${WAIT_PREFLIGHT_INTERVAL}"
    done

    [[ -n ${credentials} ]] || die "THE GRAYLOG PREFLIGHT INTERFACE DID NOT COME UP (CHECK: sudo docker compose -f ${GRAYLOG_COMPOSE_FILE} logs graylog1)"

    GL_AUTH=${credentials}

    log_info "TRY TO ACTIVATE LOCAL EVALUATION CA FOR DATANODE"
    for (( attempt = 1; attempt <= RETRY_MAX_ATTEMPTS; attempt++ ))
    do
        gl_api POST /ca/create '{"organization": "Evaluation CA"}' >/dev/null && break
        sleep "${RETRY_INTERVAL}"
    done
    gl_api POST /renewal_policy '{"mode":"Automatic","certificate_lifetime":"P90D"}' >/dev/null || fail "CA RENEWAL POLICY COULD NOT BE SET"
    gl_api POST /generate >/dev/null || fail "CERTIFICATE PROVISIONING REQUEST FAILED"
    finish_result=$(gl_api POST /status/finish-config | jq -r '.result // empty' 2>/dev/null)

    if [[ ${finish_result} != "FINISHED" ]]
    then
        die "FAILED TO ACTIVATE LOCAL EVALUATION CA, EXIT"
    fi

    log_info "SUCCESSFULLY ACTIVATED LOCAL EVALUATION CA FOR DATANODE"
}

function_createUserToken () {
    # USERNAME TTL_DAYS - prints the token
    local username=${1} ttl_days=${2} user_id token
    local GL_AUTH="${GRAYLOG_ADMIN}:${GRAYLOG_PASSWORD}"

    log_info "CREATE GRAYLOG API TOKEN FOR ACCOUNT ${username^^}"

    user_id=$(gl_api GET /users | jq -r --arg name "${username}" '.users[] | select(.username == $name) | .id' 2>/dev/null)
    if [[ -z ${user_id} || ${user_id} == "null" ]]
    then
        log_error "USER ${username^^} NOT FOUND IN GRAYLOG"
        return 1
    fi

    token=$(gl_api POST "/users/${user_id}/tokens/evaluation-${username}" "{\"token_ttl\":\"P${ttl_days}D\"}" | jq -r '.token // empty' 2>/dev/null)
    if [[ -z ${token} ]]
    then
        log_error "TOKEN FOR ${username^^} COULD NOT BE CREATED"
        return 1
    fi

    printf '%s\n' "${token}"
}

function_addSidecarConfigurationVariables () {
    local variable
    local -a variables=(
        '{"id":"","name":"nxlog_port_windows","description":"12148 tcp","content":"12148"}'
        '{"id":"","name":"beats_port_windows","description":"5044 tcp","content":"5044"}'
        '{"id":"","name":"beats_port_linux","description":"5045 tcp","content":"5045"}'
        '{"id":"","name":"beats_port_self","description":"5054 tcp","content":"5054"}'
        '{"id":"","name":"nxlog_path","description":"C:\\Program Files\\nxlog","content":"C:\\Program Files\\nxlog"}'
    )

    log_info "CREATE GRAYLOG SIDECAR CONFIGURATION VARIABLES"
    for variable in "${variables[@]}"
    do
        gl_try "CREATE SIDECAR CONFIGURATION VARIABLE $(jq -r '.name' <<<"${variable}")" \
            POST /sidecar/configuration_variables "${variable}"
    done
}

function_configurePlugins () {
    local entry grafana_payload
    local content_pack_payload='{"entity":{"parameters":{},"comment":"Activated for Evaluation"}}'
    local -a content_packs=(
        "daf6355e-2d5e-08d3-f9ba-44e84a43df1a|ACTIVATE OTX PLUGIN"
        "9350a70a-8453-f516-7041-517b4df0b832|ACTIVATE TOR EXIT NODES LIST"
        "90be5e03-cb16-c802-6462-a244b4a342f3|ACTIVATE SPAMHAUS DROP LISTS"
        "1794d39d-077f-7360-b92b-95411b05fbce|ACTIVATE WHOIS PLUGIN"
    )

    gl_try "ADD INTERNAL WEBSERVER TO ALLOWLIST" PUT /system/urlallowlist \
        '{"entries":[{"id":"5089e707-cd98-4b1d-9423-850a12272bbe","title":"Internal Webserver","value":"http://lookuptables/*","type":"regex"}],"disabled":false}'

    for entry in "${content_packs[@]}"
    do
        gl_try "${entry#*|}" POST "/system/content_packs/${entry%%|*}/1/installations" "${content_pack_payload}"
    done

    gl_try "ACTIVATE THREAT INTEL PLUGIN" PUT /system/cluster_config/org.graylog.plugins.threatintel.ThreatIntelPluginConfiguration \
        '{"tor_enabled":true,"spamhaus_enabled":true,"abusech_ransom_enabled":false}'

    gl_try "CONFIGURE FAILURE PROCESSING" PUT /plugins/org.graylog.plugins.failure/config \
        '{"persistIndexingFailure":true,"persistFailedMessage":true,"submitProcessingFailure":true,"keepFailedMessageDuplicate":true,"persistInputFailure":true}'

    gl_try "REARRANGE PROCESSING ORDER AND DISABLE AWS INSTANCE NAME LOOKUP" PUT /system/messageprocessors/config \
        '{"processor_order":[{"name":"AWS Instance Name Lookup","class_name":"org.graylog.aws.processors.instancelookup.AWSInstanceNameLookupProcessor"},{"name":"Illuminate Processor","class_name":"org.graylog.plugins.illuminate.processing.IlluminateMessageProcessor"},{"name":"Message Filter Chain","class_name":"org.graylog2.messageprocessors.MessageFilterChainProcessor"},{"name":"Stream Rule Processor","class_name":"org.graylog2.messageprocessors.StreamMatcherFilterProcessor"},{"name":"Pipeline Processor","class_name":"org.graylog.plugins.pipelineprocessor.processors.PipelineInterpreter"},{"name":"GeoIP Resolver","class_name":"org.graylog.plugins.map.geoip.processor.GeoIpProcessor"}],"disabled_processors":["org.graylog.aws.processors.instancelookup.AWSInstanceNameLookupProcessor"]}'

    # Grafana: rename the default admin, then set the password (JSON built by jq, password passed via environment)
    grafana_payload=$(jq -nc --arg login "${GRAYLOG_ADMIN}" '{name: "Evaluation Admin", login: $login}')
    GL_AUTH="admin:admin" gl_try "RECONFIGURE GRAFANA ADMIN NAME" PUT "${GRAFANA_API}/users/1" "${grafana_payload}"
    grafana_payload=$(GRAFANA_PASSWORD="${GRAYLOG_PASSWORD}" jq -nc '{password: env.GRAFANA_PASSWORD}')
    GL_AUTH="${GRAYLOG_ADMIN}:admin" gl_try "RECONFIGURE GRAFANA ADMIN PASSWORD" PUT "${GRAFANA_API}/admin/users/1/password" "${grafana_payload}"

    GL_AUTH="${GRAYLOG_ADMIN}:${GRAYLOG_PASSWORD}" gl_try "CONFIGURE PROMETHEUS CONNECTOR" POST "${GRAFANA_API}/datasources" \
        '{ "name" : "prometheus", "type" : "prometheus", "url": "http://prometheus1:9090/prometheus", "access": "proxy", "readOnly" : false, "isDefault" : true, "basicAuth" : false }'

    gl_try "ACTIVATE MCP SERVER" PUT /system/cluster_config/org.graylog.mcp.config.McpConfiguration \
        '{"enable_remote_access":true,"enable_output_schema":true,"enable_input_validation":true}'
}

function_configureSelfMonitoring () {
    local log_item="evaluation-self-monitoring"
    local title="${GRAYLOG_SELF_MONITORING_STREAM_TITLE}"
    local rule_name="10 - Self-Monitoring - Parser Graylog"
    local nl=$'\n'
    local input_id profile_id index_id stream_id pipeline_id payload

    log_info "CREATE INPUT FOR ${log_item^^} LOGS (BEATS TCP 5054)"
    payload=$(jq -nc --arg title "Port 5054 Beats | ${title}" \
        '{global: true, title: $title, type: "org.graylog.plugins.beats.Beats2Input", configuration: {port: 5054, number_worker_threads: 2, bind_address: "0.0.0.0"}}')
    input_id=$(gl_api POST /system/inputs "${payload}" | jq -r '.id // empty' 2>/dev/null)
    [[ -n ${input_id} ]] || { fail "COULD NOT CREATE THE SELF-MONITORING INPUT, SKIPPING SELF-MONITORING"; return 1; }

    log_info "CREATE FIELD TYPE PROFILE FOR ${log_item^^} LOGS"
    payload=$(jq -nc --arg title "${title}" '{
        custom_field_mappings: [
            {field: "command", type: "string"},
            {field: "event_severity", type: "string"},
            {field: "application_component", type: "string"},
            {field: "event_received", type: "date"},
            {field: "event_source_product", type: "string"}],
        name: $title, description: $title}')
    profile_id=$(gl_api POST /system/indices/index_sets/profiles "${payload}" | jq -r '.id // empty' 2>/dev/null)
    [[ -n ${profile_id} ]] || fail "COULD NOT CREATE THE FIELD TYPE PROFILE, CONTINUING WITHOUT IT"

    log_info "CREATE INDEX FOR ${log_item^^} LOGS"
    payload=$(jq -nc --arg title "${title}" --arg prefix "${log_item}" --arg profile "${profile_id}" '{
        shards: 1, replicas: 0,
        rotation_strategy_class: "org.graylog2.indexer.rotation.strategies.TimeBasedSizeOptimizingStrategy",
        rotation_strategy: {type: "org.graylog2.indexer.rotation.strategies.TimeBasedSizeOptimizingStrategyConfig", index_lifetime_min: "P30D", index_lifetime_max: "P90D"},
        retention_strategy_class: "org.graylog2.indexer.retention.strategies.DeletionRetentionStrategy",
        retention_strategy: {type: "org.graylog2.indexer.retention.strategies.DeletionRetentionStrategyConfig", max_number_of_indices: 20},
        data_tiering: {type: "hot_only", index_lifetime_min: "P30D", index_lifetime_max: "P90D"},
        title: $title, description: $title, index_prefix: $prefix, index_analyzer: "standard",
        index_optimization_max_num_segments: 1, index_optimization_disabled: false,
        field_type_refresh_interval: 5000,
        field_type_profile: (if $profile == "" then null else $profile end),
        use_legacy_rotation: false, writable: true}')
    index_id=$(gl_api POST /system/indices/index_sets "${payload}" | jq -r '.id // empty' 2>/dev/null)
    [[ -n ${index_id} ]] || { fail "COULD NOT CREATE THE SELF-MONITORING INDEX SET, SKIPPING SELF-MONITORING"; return 1; }

    log_info "CREATE STREAM FOR ${log_item^^} LOGS"
    payload=$(jq -nc --arg title "${title}" --arg index "${index_id}" \
        '{entity: {description: "Stream containing messages created by Graylog Stack", title: $title, remove_matches_from_default_stream: true, matching_type: "OR", index_set_id: $index}}')
    stream_id=$(gl_api POST /streams "${payload}" | jq -r '.stream_id // empty' 2>/dev/null)
    [[ -n ${stream_id} ]] || { fail "COULD NOT CREATE THE SELF-MONITORING STREAM, SKIPPING SELF-MONITORING"; return 1; }

    payload=$(jq -nc --arg description "${log_item}-beats" --arg input "${input_id}" \
        '{field: "gl2_source_input", description: $description, type: 1, inverted: false, value: $input}')
    gl_try "CREATE STREAM RULE FOR ${log_item^^} LOGS (BEATS)" POST "/streams/${stream_id}/rules" "${payload}"

    log_info "CREATE PIPELINE FOR ${log_item^^} LOGS (BEATS)"
    payload=$(jq -nc --arg title "${title}" --arg source "pipeline \"${title}\"${nl}stage 10 match either${nl}end" \
        '{title: $title, description: $title, stages: [{stage: 10, rules: [], match: "EITHER"}], source: $source, has_deprecated_functions: false}')
    pipeline_id=$(gl_api POST /system/pipelines/pipeline "${payload}" | jq -r '.id // empty' 2>/dev/null)

    if [[ -n ${pipeline_id} ]]
    then
        payload=$(jq -nc --arg pipeline "${pipeline_id}" --arg stream "${stream_id}" '{pipeline_id: $pipeline, stream_ids: [$stream]}')
        gl_try "CONNECT PIPELINE FOR ${log_item^^} LOGS (BEATS) TO MONITORING STREAM" POST /system/pipelines/connections/to_pipeline "${payload}"

        payload=$(jq -nc --arg id "${pipeline_id}" --arg title "${title}" --arg rule "${rule_name}" \
            --arg source "pipeline \"${title}\"${nl}stage 10 match either${nl}rule \"${rule_name}\"${nl}end" \
            '{id: $id, _scope: "DEFAULT", title: $title, description: $title, source: $source, stages: [{stage: 10, match: "EITHER", rules: [$rule]}], errors: null, has_deprecated_functions: null}')
        gl_try "CONNECT PIPELINE RULES FOR ${log_item^^} LOGS (BEATS)" PUT "/system/pipelines/pipeline/${pipeline_id}" "${payload}"
    else
        fail "COULD NOT CREATE THE SELF-MONITORING PIPELINE"
    fi

    log_info "START STREAM FOR ${log_item^^} LOGS"
    function_resumeStream "${stream_id}" "${title}"
}

function_displayClusterId () {
    local cluster_id

    if ! printf '  ADMINUSER: "%s"\n  PASSWORD: "%s"\n' "${GRAYLOG_ADMIN}" "${GRAYLOG_PASSWORD}" \
        | sudo tee "${GRAYLOG_CREDENTIALS_FILE}" >/dev/null
    then
        fail "COULD NOT WRITE ${GRAYLOG_CREDENTIALS_FILE} - NOTE YOUR CREDENTIALS (ADMIN USER: ${GRAYLOG_ADMIN})"
    elif ! sudo chown "root:${INSTALL_GROUP}" "${GRAYLOG_CREDENTIALS_FILE}" || ! sudo chmod 0640 "${GRAYLOG_CREDENTIALS_FILE}"
    then
        fail "COULD NOT RESTRICT THE PERMISSIONS OF ${GRAYLOG_CREDENTIALS_FILE}"
    fi

    cluster_id=$(curl -s --noproxy '*' --max-time 10 "${GRAYLOG_API}" | jq -r '.cluster_id // "UNKNOWN"' 2>/dev/null)
    cluster_id=${cluster_id:-UNKNOWN}
    if [[ ${cluster_id} == "UNKNOWN" ]]
    then
        fail "COULD NOT READ THE CLUSTER-ID FROM ${GRAYLOG_API} - CHECK IT UNDER System > Overview"
    fi

    echo ""
    echo -e "[INFO] - \e[5;34mGRAYLOG IS NOW READY FOR TESTING\e[0m"
    echo ""
    echo -e "[INFO] - SYSTEM URL: \e[4;33mhttp(s)://${GRAYLOG_FQDN}\e[0m"
    echo -e "[INFO] - WINDOWS ACCESS: \e[1;32m\\\\\\\\${GRAYLOG_FQDN}\e[0m (SMB)"
    echo -e "[INFO] - CREDENTIALS STORED IN: \e[0;37m${GRAYLOG_CREDENTIALS_FILE}\e[0m"
    echo -e "[INFO] - FOR ADDITIONAL CONFIGURATIONS PLEASE DO REVIEW: \e[0;37m${GRAYLOG_PATH}/${GRAYLOG_SERVER_ENV}\e[0m"
    echo ""
    echo "       ********************************************************"
    echo "       *                                                      *"
    printf "       * CLUSTER-ID: \e[1;31m%-40s\e[0m *\n" "${cluster_id^^}"
    echo "       *                                                      *"
    echo "       ********************************************************"
    echo ""
    log_info "CLUSTER-ID: ${cluster_id^^}"
    echo "[INFO] - GRAYLOG STACK WILL RESTART AFTER ADDING THE LICENSE"
}

function_hasLicense () {
    # enterprise|security - returns 0 if active, 1 if not (yet) active, 2 if the status could not be read
    local license_status

    if ! license_status=$(gl_api GET /plugins/org.graylog.plugins.license/licenses/status)
    then
        log_error "COULD NOT READ THE LICENSE STATUS"
        return 2
    fi

    jq -e --arg subject "/license/${1}" '[.[] | .[]? | objects] | any(.active == true and .license.subject == $subject)' \
        <<<"${license_status}" >/dev/null 2>&1
}

function_waitForLicense () {
    # enterprise|security - exits (to retry with the next cron run) unless the license is active
    local rc

    function_hasLicense "${1}"
    rc=$?

    case ${rc} in
        0) log_info "${1^^} LICENSE IS ACTIVE" ;;
        1) log_info "WAIT FOR ${1^^} LICENSE TO BE AVAILABLE"; exit 0 ;;
        *) log_warn "COULD NOT CHECK THE ${1^^} LICENSE, RETRYING WITH THE NEXT RUN"; exit 0 ;;
    esac
}

function_restartGraylogContainer () {
    local containers=${1} container

    log_info "STOP CONTAINER(S) ${containers^^}"
    # shellcheck disable=SC2086 # word splitting intended
    run_logged compose down --remove-orphans ${containers} || return 1

    # Start one by one, in the given order (the first one becomes the LEADER)
    for container in ${containers}
    do
        log_info "START CONTAINER ${container^^}"
        run_logged compose up -d --quiet-pull --remove-orphans "${container}" || return 1
    done
}

function_startGraylogStack () {
    log_info "START GRAYLOG STACK"
    run_logged compose up -d --quiet-pull --remove-orphans || die "THE GRAYLOG STACK COULD NOT BE STARTED (DETAILS: ${LOG_FILE})"
    sleep 5
}

function_createInputs () {
    local input input_id input_list
    local -a inputs=(
        # Port 5140 Syslog UDP Input for Network Devices
        '{ "global": true, "title": "Port 5140 UDP Syslog | Evaluation Input", "type": "org.graylog2.inputs.syslog.udp.SyslogUDPInput", "configuration": { "port": 5140, "number_worker_threads": 2, "bind_address": "0.0.0.0" }}'
        # Port 5140 Syslog TCP Input for Network Devices
        '{ "global": true, "title": "Port 5140 TCP Syslog | Evaluation Input", "type": "org.graylog2.inputs.syslog.tcp.SyslogTCPInput", "configuration": { "port": 5140, "number_worker_threads": 2, "bind_address": "0.0.0.0" }}'
        # Port 5044 Beats Input for Windows - Winlogbeat, Filebeat
        '{ "global": true, "title": "Port 5044 Beats | Evaluation Input", "type": "org.graylog.plugins.beats.Beats2Input", "configuration": { "port": 5044, "number_worker_threads": 2, "bind_address": "0.0.0.0" }}'
        # Port 5045 Beats Input for Linux - Auditbeat, Filebeat
        '{ "global": true, "title": "Port 5045 Beats | Evaluation Input", "type": "org.graylog.plugins.beats.Beats2Input", "configuration": { "port": 5045, "number_worker_threads": 2, "bind_address": "0.0.0.0" }}'
        # Port 5555 RAW TCP Input
        '{ "global": true, "title": "Port 5555 TCP RAW | Evaluation Input", "type": "org.graylog2.inputs.raw.tcp.RawTCPInput", "configuration": { "port": 5555, "number_worker_threads": 2, "bind_address": "0.0.0.0" }}'
        # Port 5555 RAW UDP Input
        '{ "global": true, "title": "Port 5555 UDP RAW | Evaluation Input", "type": "org.graylog2.inputs.raw.udp.RawUDPInput", "configuration": { "port": 5555, "number_worker_threads": 2, "bind_address": "0.0.0.0" }}'
        # Port 6514 Syslog TCP over TLS Input for Network Devices (TLS must be enabled once certificates are in place)
        '{ "global": true, "title": "Port 6514 TCP Syslog over TLS | Evaluation Input", "type": "org.graylog2.inputs.syslog.tcp.SyslogTCPInput", "configuration": { "port": 6514, "number_worker_threads": 2, "bind_address": "0.0.0.0", "tls_cert_file": "/etc/graylog/server/input_tls/cert.crt", "tls_key_file": "/etc/graylog/server/input_tls/tls.key", "tls_enable": false, "tls_key_password": "" }}'
        # Port 12148 GELF TCP Input for NXLog
        '{ "global": true, "title": "Port 12148 TCP GELF | Evaluation Input", "type": "org.graylog2.inputs.gelf.tcp.GELFTCPInput", "configuration": { "port": 12148, "number_worker_threads": 2, "bind_address": "0.0.0.0" }}'
        # Port 12201 GELF TCP Input
        '{ "global": true, "title": "Port 12201 TCP GELF | Evaluation Input", "type": "org.graylog2.inputs.gelf.tcp.GELFTCPInput", "configuration": { "port": 12201, "number_worker_threads": 2, "bind_address": "0.0.0.0" }}'
        # Port 12201 GELF UDP Input
        '{ "global": true, "title": "Port 12201 UDP GELF | Evaluation Input", "type": "org.graylog2.inputs.gelf.udp.GELFUDPInput", "configuration": { "port": 12201, "number_worker_threads": 2, "bind_address": "0.0.0.0" }}'
        # Port 13301 13302 TCP Input for Enterprise Forwarder
        '{"type":"org.graylog.plugins.forwarder.input.ForwarderServiceInput","configuration":{"forwarder_bind_address":"0.0.0.0","forwarder_message_transmission_port":13301,"forwarder_configuration_port":13302,"forwarder_grpc_enable_tls":false,"forwarder_grpc_tls_trust_chain_cert_file":"","forwarder_grpc_tls_private_key_file":"","forwarder_grpc_tls_private_key_file_password":""},"title":"Graylog Enterprise Forwarder | Evaluation Input","global":true}'
    )

    if [[ ${GRAYLOG_LICENSE_ENTERPRISE} != "true" ]]
    then
        return 0
    fi

    # Adding Inputs to make sure Ports map to Nginx configuration
    log_info "CREATE EVALUATION INPUTS"
    for input in "${inputs[@]}"
    do
        gl_try "CREATE INPUT: $(jq -r '.title' <<<"${input}")" POST /system/inputs "${input}"
    done

    log_info "START ALL EVALUATION INPUTS"
    if ! input_list=$(gl_api GET /system/inputs)
    then
        fail "COULD NOT READ THE LIST OF INPUTS - START THE INPUTS MANUALLY (System > Inputs)"
        return 1
    fi

    for input_id in $(jq -r '.inputs[].id' <<<"${input_list}" 2>/dev/null)
    do
        gl_try "START INPUT ${input_id}" PUT "/cluster/inputstates/${input_id}"
    done
}

function_isStreamRunning () {
    # STREAM_ID - returns 0 if running, 1 if paused, 2 if the state is unknown
    local disabled
    disabled=$(gl_api GET "/streams/${1}" | jq -r '.disabled' 2>/dev/null)
    case "${disabled}" in
        false) return 0 ;;
        true)  return 1 ;;
        *)     return 2 ;;
    esac
}

function_resumeStream () {
    # STREAM_ID [TITLE] - starts a paused stream; a running stream is not an error
    local stream_id=${1} title=${2:-${1}} message

    if function_isStreamRunning "${stream_id}"
    then
        log_info "STREAM ${title^^} IS ALREADY RUNNING"
        return 0
    fi

    if GL_EXPECTED_STATUS="400" gl_api POST "/streams/${stream_id}/resume" >/dev/null
    then
        log_info "STREAM ${title^^} STARTED"
        return 0
    fi

    # Graylog answers 400 "The stream cannot be resumed." for streams that are
    # already running or cannot be paused at all (default/system streams)
    if [[ ${GL_LAST_STATUS} == "400" ]]
    then
        if function_isStreamRunning "${stream_id}"
        then
            log_info "STREAM ${title^^} IS RUNNING (RESUME NOT REQUIRED)"
            return 0
        fi
        message=$(jq -r '.message // empty' <<<"${GL_LAST_RESPONSE}" 2>/dev/null)
        fail "STREAM ${title^^} COULD NOT BE STARTED: ${message:-HTTP 400}"
        return 1
    fi

    fail "STREAM ${title^^} COULD NOT BE STARTED (HTTP ${GL_LAST_STATUS}, DETAILS: ${LOG_FILE})"
    return 1
}

function_startAllStreams () {
    local streams stream_id disabled title started=0 running=0 failed=0

    log_info "START ALL STREAMS"
    if ! streams=$(gl_api GET /streams)
    then
        fail "COULD NOT READ THE LIST OF STREAMS, SKIPPING STREAM START"
        return 1
    fi

    while IFS=$'\t' read -r stream_id disabled title
    do
        [[ -n ${stream_id} ]] || continue

        # Only paused streams need (and accept) a resume call
        if [[ ${disabled} != "true" ]]
        then
            log_info "STREAM ${title^^} IS ALREADY RUNNING"
            (( running++ ))
            continue
        fi

        if function_resumeStream "${stream_id}" "${title}"
        then
            (( started++ ))
        else
            (( failed++ ))
        fi
    done < <(jq -r '.streams[] | [.id, (.disabled | tostring), .title] | @tsv' <<<"${streams}" 2>/dev/null)

    log_info "STREAMS: ${started} STARTED, ${running} ALREADY RUNNING, ${failed} FAILED"
    (( failed == 0 ))
}

function_configureEvaluationSetup () {
    local archive_backend warm_tier_name index_set_template active_backend payload retention

    if [[ ${GRAYLOG_LICENSE_ENTERPRISE} != "true" ]]
    then
        return 0
    fi

    gl_try "ACTIVATE HEADER BADGE" PUT /system/cluster_config/org.graylog.plugins.customization.HeaderBadge \
        '{"badge_enable": true,"badge_color": "#689f38","badge_text": "EVAL"}'

    gl_try "ACTIVATE EVALUATION NOTIFICATION" POST /plugins/org.graylog.plugins.customization/notifications \
        '{"title":"Evaluation System","shortMessage":"DO NOT USE IN PRODUCTION","longMessage":"This System was set up for a Graylog Product Evaluation and MUST NOT be used in production. For a secure and production-ready setup please get in touch with your Graylog Customer Success Manager who will help you to deploy your Graylog Stack following best practices.","isActive":true,"isDismissible":true,"atLogin":true,"isGlobal":false,"variant":"warning","hiddenTitle":false}'

    # gl_try "ACTIVATE GRAYLOG v5 COLOUR SCHEME" POST /plugins/org.graylog.plugins.customization/theme '{"light":{"global":{"background":"#eeeff2","link":"#578dcc"},"brand":{"tertiary":"#3e434c"},"variant":{"default":"#9aa8bd","danger":"#eb5454","info":"#578dcc","primary":"#697586","success":"#7eb356","warning":"#eedf64"}},"dark":{"global":{"background":"#222222","contentBackground":"#303030","link":"#629de2"},"brand":{"tertiary":"#ffffff"},"variant":{"default":"#595959","danger":"#e74c3c","info":"#578dcc","primary":"#697586","success":"#709e4c","warning":"#e3d45f"}}}'

    log_info "CONFIGURE ARCHIVE"
    archive_backend=$(gl_api GET /plugins/org.graylog.plugins.archive/config | jq -r '.backend_id // empty' 2>/dev/null)
    if [[ -n ${archive_backend} ]]
    then
        payload=$(jq -nc --arg backend "${archive_backend}" '{
            archive_path: "/usr/share/graylog/data/archives", max_segment_size: 524288000,
            segment_filename_prefix: "archive-segment", segment_compression_type: "GZIP",
            metadata_filename: "archive-metadata.json", histogram_bucket_size: 86400000,
            restore_index_batch_size: 1000, excluded_streams: [], segment_checksum_type: "CRC32",
            backend_id: $backend, archive_failure_threshold: 1, retention_time: 30,
            restrict_to_leader: true, parallelize_archive_creation: true}')
        gl_try "CONFIGURE ARCHIVE" PUT /plugins/org.graylog.plugins.archive/config "${payload}"
    else
        fail "NO ARCHIVE BACKEND FOUND, SKIPPING ARCHIVE CONFIGURATION"
    fi

    log_info "ACTIVATE WARM TIER (LOCAL FILESTORE OR MOUNTPOINT)"
    warm_tier_name=$(gl_api POST /plugins/org.graylog.plugins.datatiering/datatiering/repositories \
        '{"type":"fs","name":"warm_tier","location":"/var/lib/graylog/warm_tier"}' | jq -r '.name // empty' 2>/dev/null)

    if [[ -n ${warm_tier_name} ]]
    then
        log_info "CREATE INDEX SET TEMPLATE FOR EVALUATION (SHORT RETENTION)"
        payload=$(jq -nc --arg warm "${warm_tier_name}" '{
            title: "Evaluation Storage", description: "Use case: Graylog Product Evaluation",
            index_set_config: {shards: 1, replicas: 0, index_optimization_max_num_segments: 1,
                index_optimization_disabled: false, field_type_refresh_interval: 5000,
                data_tiering: {type: "hot_warm", index_lifetime_min: "P10D", index_lifetime_max: "P12D",
                    warm_tier_enabled: true, index_hot_lifetime_min: "P8D",
                    warm_tier_repository_name: $warm, archive_before_deletion: true},
                index_analyzer: "standard", use_legacy_rotation: false}}')
        index_set_template=$(gl_api POST /system/indices/index_sets/templates "${payload}" | jq -r '.id // empty' 2>/dev/null)

        if [[ -n ${index_set_template} ]]
        then
            gl_try "CONFIGURE INDEX SET TEMPLATE FOR EVALUATION AS DEFAULT" PUT /system/indices/index_set_defaults \
                "{\"id\":\"${index_set_template}\"}"
        else
            fail "COULD NOT CREATE THE EVALUATION INDEX SET TEMPLATE"
        fi
    else
        fail "COULD NOT CREATE THE WARM TIER, SKIPPING THE EVALUATION INDEX SET TEMPLATE"
    fi

    log_info "ACTIVATE DATALAKE (LOCAL FILESTORE OR MOUNTPOINT)"
    active_backend=$(gl_api POST /plugins/org.graylog.plugins.datalake/data_lake/backends \
        '{"title":"File System Data Lake","description":"Data Lake on the local Filesystem","settings":{"type":"fs-1","output_path":"/usr/share/graylog/data/datalake","usage_threshold":80}}' \
        | jq -r '.id // empty' 2>/dev/null)

    if [[ -n ${active_backend} ]]
    then
        # First activate the backend, then set the max retention (7 days)
        for retention in null '"P7D"'
        do
            payload=$(jq -nc --arg backend "${active_backend}" --argjson retention "${retention}" '{
                active_backend: $backend, iceberg_commit_interval: "PT15M", iceberg_target_file_size: 536870912,
                parquet_row_group_size: 134217728, parquet_page_size: 8192, journal_reader_batch_size: 500,
                optimize_job_enabled: true, optimize_job_interval: "PT1H", optimize_max_concurrent_file_rewrites: null,
                parallel_retrieval_enabled: true, retrieval_convert_threads: -1, retrieval_convert_batch_size: 1,
                retrieval_inflight_requests: 3, retrieval_bulk_batch_size: 2500, retention_time: $retention}')
            gl_try "CONFIGURE DATALAKE (RETENTION: ${retention//\"/})" PUT /plugins/org.graylog.plugins.datalake/data_lake/config "${payload}"
        done
    else
        fail "COULD NOT CREATE THE DATALAKE BACKEND"
    fi

    # Datalake for the Self-Monitoring stream (disabled):
    # stream_id=$(gl_api GET /streams | jq -r --arg title "${GRAYLOG_SELF_MONITORING_STREAM_TITLE}" '.streams[] | select(.title == $title) | .id')
    # gl_try "CONFIGURE DATALAKE FOR SELF-MONITORING STREAM" POST /plugins/org.graylog.plugins.datalake/data_lake/stream/config/enable "{\"stream_ids\":[\"${stream_id}\"],\"enabled\":true}"
}

function_addSidecarConfigurationTags () {
    # NAME_REGEX TAG [wait] - sets TAG on all sidecar configurations whose name matches NAME_REGEX
    local name_regex=${1} tag=${2} wait_for_templates=${3:-}
    local attempt=1 configuration_ids configuration_id configuration name payload

    while true
    do
        configuration_ids=$(gl_api GET /sidecar/configurations \
            | jq -r --arg regex "${name_regex}" '.configurations[] | select(.name | test($regex)) | .id' 2>/dev/null)

        [[ -n ${configuration_ids} ]] && break

        if [[ ${wait_for_templates} != "wait" ]] || (( attempt >= RETRY_MAX_ATTEMPTS ))
        then
            fail "NO SIDECAR CONFIGURATIONS MATCHING '${name_regex}' FOUND, SKIPPING TAG ${tag^^}"
            return 1
        fi

        log_info "WAIT FOR GRAYLOG SIDECAR COLLECTOR TEMPLATES TO BECOME CONFIGURABLE (ATTEMPT ${attempt}/${RETRY_MAX_ATTEMPTS})"
        (( attempt++ ))
        sleep "${RETRY_INTERVAL}"
    done

    for configuration_id in ${configuration_ids}
    do
        # One GET per configuration; jq builds the PUT body
        if ! configuration=$(gl_api GET "/sidecar/configurations/${configuration_id}")
        then
            fail "COULD NOT READ SIDECAR CONFIGURATION ${configuration_id}"
            continue
        fi
        name=$(jq -r '.name' <<<"${configuration}")
        payload=$(jq -c --arg tag "${tag}" '{id, name, color, collector_id, template, tags: [$tag]}' <<<"${configuration}")

        gl_try "CREATE SIDECAR CONFIGURATION TAG ${tag^^} ON ${name^^}" PUT "/sidecar/configurations/${configuration_id}" "${payload}"
    done
}

function_enableGraylogSidecar () {

    log_info "ACTIVATE AND START GRAYLOG SIDECAR ON HOST"
    if ! command -v graylog-sidecar >/dev/null 2>&1
    then
        fail "GRAYLOG SIDECAR IS NOT INSTALLED ON THIS HOST, SKIPPING SERVICE ACTIVATION"
        return 1
    fi

    # Only install the service if the unit does not exist yet
    if ! systemctl cat graylog-sidecar.service >/dev/null 2>&1
    then
        run_logged sudo graylog-sidecar -service install \
            || { fail "COULD NOT INSTALL THE GRAYLOG SIDECAR SERVICE"; return 1; }
    fi
    run_logged sudo systemctl enable --now graylog-sidecar || { fail "GRAYLOG SIDECAR COULD NOT BE STARTED"; return 1; }

    if ! systemctl is-active --quiet graylog-sidecar
    then
        fail "GRAYLOG SIDECAR IS NOT RUNNING (CHECK: sudo journalctl -u graylog-sidecar)"
        return 1
    fi
}

function_configureEnterpriseFeatures () {
    local payload
    local illuminate_processing_pack_ids='["7b319ad0-352c-48b9-b7d9-877fc1720164","core-gim-enforcement","fortigate-content-pack","illuminate-linux-auditbeat","0137f1f8-1a6e-449b-a46c-6bb37f2f0c53","3f3c1eea-200a-4381-83ae-aadd5d6a0d6e","illuminate-o365","5551b8a8-6459-446f-9ea8-63368bb39414","illuminate-defender","b1f235ed-f185-43af-b5d1-d3fb37f217a1","2e6cedfb-21f9-485f-8bdc-326349651b0f","windows-security","c3c902ad-9113-439e-b92b-5cd4bfa26696","d1aea731-2b18-4e47-9366-c526641f6dbd"]'
    # FIXME: "b95c89b7-36e1-43b6-9714-b6b25e7cec04e" is not a valid UUID (13 characters in the
    #        last group) - please verify this pack id against the Illuminate bundle.
    local illuminate_spotlight_pack_ids='["cbfc3ae6-6a59-4841-a691-ea6db41b62d0","d01d7647-99a5-4914-b417-ca5cd1e37196","085d8f0e-2bee-44b2-b040-d7a11a1da2fe","90e37be0-d112-44f8-afe7-eadcafbe4ba3","557d2945-8d6d-445b-ae5e-9388ee89f128","61d75c3e-3551-4b97-bbb5-ea8181472cb0","a2750c63-fb7c-4ff6-b10b-32171a2c96e9","4e3ba1a6-7400-40d1-b7f8-efa44bc5bfeb","3e40d288-5794-44e9-88b4-b590de3514b8","977b3617-be58-4f6c-9db6-06f72dbab306","e1629dcb-6419-4d73-b4a8-577f01278f35","f39f9b0d-c24b-42f2-982b-839441ef3c27","237e73a4-678b-4b9a-87ac-ff2f86e34563","a60c3607-a25a-4b5c-a565-94b6944f850b","b95c89b7-36e1-43b6-9714-b6b25e7cec04","9f195288-9709-4f87-b2ec-e53cf94965dd"]'

    if [[ ${GRAYLOG_LICENSE_ENTERPRISE} != "true" ]]
    then
        log_info "NO ENTERPRISE LICENSE AVAILABLE, SKIPPING ILLUMINATE ACTIVATION"
        return 0
    fi

    payload="{\"entity\":{\"processing_pack_ids\":${illuminate_processing_pack_ids},\"spotlight_pack_ids\":${illuminate_spotlight_pack_ids}}}"
    if gl_try "ACTIVATE ILLUMINATE PACKAGES" POST /plugins/org.graylog.plugins.illuminate/bundles/latest/enable_packs "${payload}"
    then
        sleep 90
        log_info "ILLUMINATE PACKAGES ACTIVATED"
    fi
}

function_configureSecurityFeatures () {
    local active_ai="" attempt payload
    local illuminate_security_processing_pack_ids='["05dc479f-9659-476b-b888-9fdaae3a7777","7b319ad0-352c-48b9-b7d9-877fc1720164"]'
    local illuminate_security_spotlight_pack_ids='["10da1609-54b1-4e73-8757-a5326379ad26","5289b02d-ebb9-4c93-baf8-baf05e1c138b","0a9389f4-d3c0-4d8f-8025-0f29ff0355d7","90e37be0-d112-44f8-afe7-eadcafbe4ba3","fd45efec-c972-4616-a9e2-d68930ce9478"]'

    if [[ ${GRAYLOG_LICENSE_SECURITY} != "true" ]]
    then
        log_info "NO SECURITY LICENSE AVAILABLE, SKIPPING ILLUMINATE ACTIVATION"
        return 0
    fi

    for (( attempt = 1; attempt <= RETRY_MAX_ATTEMPTS; attempt++ ))
    do
        log_info "DISABLE INVESTIGATION AI REPORTS (ATTEMPT ${attempt}/${RETRY_MAX_ATTEMPTS})"
        gl_api DELETE /plugins/org.graylog.plugins.securityapp.investigations/ai/config/ai_enabled >/dev/null \
            || log_warn "DISABLING INVESTIGATION AI REPORTS FAILED IN ATTEMPT ${attempt} (HTTP ${GL_LAST_STATUS})"
        active_ai=$(gl_api GET /plugins/org.graylog.plugins.securityapp.investigations/ai/config | jq -r '.investigations_ai_reports_enabled' 2>/dev/null)

        # Done as soon as Graylog answers with anything except "true"
        [[ -n ${active_ai} && ${active_ai} != "true" ]] && break
        sleep "${RETRY_INTERVAL}"
    done

    if [[ -z ${active_ai} || ${active_ai} == "true" ]]
    then
        fail "COULD NOT DISABLE INVESTIGATION AI REPORTS AFTER ${RETRY_MAX_ATTEMPTS} ATTEMPTS, CONTINUING"
    fi

    payload="{\"entity\":{\"processing_pack_ids\":${illuminate_security_processing_pack_ids},\"spotlight_pack_ids\":${illuminate_security_spotlight_pack_ids}}}"
    if gl_try "ACTIVATE ILLUMINATE SECURITY PACKAGES" POST /plugins/org.graylog.plugins.illuminate/bundles/latest/enable_packs "${payload}"
    then
        sleep 90
        log_info "ILLUMINATE SECURITY PACKAGES ACTIVATED"
    fi
}

function_configureSecurityAlerts () {
    local skip_json definitions id title enabled=0 failed=0
    local -a disabled_events=(
        "DNS traffic to unapproved DNS Server (Security Core: Perimeter)"
        "Excessive Outbound Connections from Single Host (Security Core: Endpoint)"
        "Large Outbound Transfer - Greater than 100MB (Security Core: Perimeter)"
    )

    skip_json=$(jq -nc '$ARGS.positional' --args "${disabled_events[@]}")

    if ! definitions=$(gl_api GET "/events/definitions/paginated?page=1&per_page=500")
    then
        fail "COULD NOT READ EVENT DEFINITIONS, SKIPPING SECURITY ALERTS"
        return 1
    fi

    if ! jq -e '.elements | type == "array"' <<<"${definitions}" >/dev/null 2>&1
    then
        fail "UNEXPECTED RESPONSE WHEN READING EVENT DEFINITIONS, SKIPPING SECURITY ALERTS"
        return 1
    fi

    while IFS=$'\t' read -r id title
    do
        [[ -n ${id} ]] || continue
        if gl_api PUT "/events/definitions/${id}/schedule" >/dev/null
        then
            log_info "ENABLED EVENT DEFINITION: ${id} - ${title}"
            (( enabled++ ))
        else
            fail "FAILED TO ENABLE EVENT DEFINITION \"${title}\" (HTTP ${GL_LAST_STATUS})"
            (( failed++ ))
        fi
    done < <(jq -r --argjson skip "${skip_json}" '
        .elements[]
        | select(.state == "DISABLED")
        | select(.title | IN($skip[]) | not)
        | [.id, .title] | @tsv' <<<"${definitions}" 2>/dev/null)

    log_info "EVENT DEFINITIONS: ${enabled} ENABLED, ${failed} FAILED"
    (( failed == 0 ))
}

function_restoreSystem () {
    echo "[INFO] - GRAYLOG INSTALLATION FAILED - DELETING TRACES"
    echo "[INFO] - GRAYLOG INSTALLATION FAILED - PLEASE RESTART THE PROCESS AFTERWARDS"
    log_info "GRAYLOG INSTALLATION FAILED - DELETING TRACES"

    [[ -t 0 ]] || die "THE RESET MUST BE CONFIRMED INTERACTIVELY - RUN THIS SCRIPT FROM A TERMINAL"
    read -rp "$(input_prompt "PRESS ENTER TO CONTINUE...")"

    [[ -x ${GRAYLOG_RESET_SCRIPT} ]] || die "RESET SCRIPT ${GRAYLOG_RESET_SCRIPT} NOT FOUND - PLEASE RESTORE YOUR VM SNAPSHOT"
    exec "${GRAYLOG_RESET_SCRIPT}"
}

function_removeAdminToken () {
    local tokens token_ids token_id removed=0 failed=0
    local manual_hint="REMOVE THE 'evaluation-*' TOKEN OF THE ADMIN USER MANUALLY (System > Users and Teams > Edit Tokens)"

    log_info "REMOVE TEMPORARY ADMIN TOKEN(S)"

    # Called directly (not in $(...)) so that GL_LAST_STATUS reflects this request
    if ! gl_api GET /users/local:admin/tokens >/dev/null
    then
        fail "COULD NOT LIST THE ADMIN TOKENS (HTTP ${GL_LAST_STATUS:-000}) - ${manual_hint}"
        return 1
    fi
    tokens=${GL_LAST_RESPONSE}

    if ! token_ids=$(jq -r '.tokens[] | select(.name | test("^evaluation-")) | .id' <<<"${tokens}" 2>/dev/null)
    then
        fail "UNEXPECTED RESPONSE WHEN LISTING THE ADMIN TOKENS - ${manual_hint}"
        return 1
    fi

    if [[ -z ${token_ids} ]]
    then
        warn "NO TEMPORARY ADMIN TOKEN FOUND (ALREADY REMOVED?)"
        return 0
    fi

    # The token in use is one of these: once it is deleted, further calls return 401
    for token_id in ${token_ids}
    do
        if gl_api DELETE "/users/local:admin/tokens/${token_id}" >/dev/null
        then
            log_info "REMOVED TEMPORARY ADMIN TOKEN ${token_id}"
            (( removed++ ))
        else
            fail "COULD NOT REMOVE ADMIN TOKEN ${token_id} (HTTP ${GL_LAST_STATUS:-000}) - ${manual_hint}"
            (( failed++ ))
        fi
    done

    log_info "ADMIN TOKENS: ${removed} REMOVED, ${failed} FAILED"
    (( failed == 0 ))
}

function_configureTestSystem () {
    local script="${HOME}/graylog-cluster.sh"

    if [[ -f ${script} ]]
    then
        log_info "RUN ${script}"
        bash "${script}" || fail "${script} FAILED"
    fi
}

###############################################################################
#
# Graylog Installation

function_runInstallation () {

    function_checkInstallUser

    # Keep the sudo timestamp alive while the script runs
    ( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) >/dev/null 2>&1 &
    KEEPALIVE_PID=$!

    clear

    echo "[INFO] - GET SYSTEM PREPARED FOR INSTALLATION, HANG ON"

    function_checkInternetConnectivity
    function_checkPatchLevel
    function_installScriptDependencies

    function_checkSystemRequirements
    function_checkSnapshot

    function_defineAdminName
    function_defineAdminPassword
    function_getSystemFqdn

    sudo mkdir -p "${GRAYLOG_PATH}" || die "COULD NOT CREATE ${GRAYLOG_PATH}"
    function_writeState "started" || die "COULD NOT WRITE ${GRAYLOG_STATE_FILE}"
    INSTALL_PHASE="install"

    echo "[INFO] - INSTALL DOCKER-CE"
    function_installDocker

    echo "[INFO] - INSTALL GRAYLOG STACK, GIVE IT SOME TIME"
    function_installGraylogStack
    function_startGraylogStack
    function_addDataNodesToCluster

    echo "[INFO] - DOWNLOAD SIDECAR AND COLLECTOR BINARIES"
    run_step "DOWNLOAD GRAYLOG COLLECTOR" function_downloadGraylogCollectorBinaries
    run_step "DOWNLOAD GRAYLOG SIDECAR" function_downloadGraylogSidecarBinaries
    run_step "DOWNLOAD BEATS" function_downloadBeatsBinaries
    run_step "PREPARE NXLOG README" function_downloadNxlogBinaries
    function_checkSystemAvailability || die "GRAYLOG DID NOT BECOME AVAILABLE"

    GRAYLOG_ADMIN_TOKEN=$(function_createUserToken "${GRAYLOG_ADMIN}" 14)        || die "COULD NOT CREATE AN API TOKEN FOR ${GRAYLOG_ADMIN^^}"
    GRAYLOG_SIDECAR_TOKEN=$(function_createUserToken "${GRAYLOG_SIDECAR}" 730)   || die "COULD NOT CREATE AN API TOKEN FOR ${GRAYLOG_SIDECAR^^}"
    GL_AUTH="${GRAYLOG_ADMIN_TOKEN}:token"

    echo "[INFO] - INSTALL SIDECAR ON HOST"
    run_step "INSTALL GRAYLOG SIDECAR ON HOST" function_installGraylogSidecarOnEvaluationHost "${GRAYLOG_SIDECAR_TOKEN}"

    echo "[INFO] - PREPARE SYSTEM PLUGINS AND FUNCTIONS"
    run_step "PREPARE WINDOWS SIDECAR CONFIGURATION" function_prepareSidecarConfiguration "${GRAYLOG_SIDECAR_TOKEN}"
    run_step "CONFIGURE PLUGINS" function_configurePlugins

    # Make sure the Container being restarted is the LEADER node, as the automatic Content Pack installation is executed by the LEADER
    function_restartGraylogContainer "graylog1" || die "COULD NOT RESTART GRAYLOG1 (DETAILS: ${LOG_FILE})"
    function_checkSystemAvailability || die "GRAYLOG DID NOT BECOME AVAILABLE AFTER RESTART"

    run_step "CREATE SIDECAR CONFIGURATION VARIABLES" function_addSidecarConfigurationVariables
    # needs to run after configuration variables have been created
    run_step "TAG HOST SIDECAR CONFIGURATIONS" function_addSidecarConfigurationTags "^my-self-" "${GRAYLOG_SIDECAR_TAG}" wait
    # only required until https://github.com/Graylog2/graylog2-server/issues/24398 is resolved
    run_step "TAG WINDOWS SIDECAR CONFIGURATIONS" function_addSidecarConfigurationTags "my-windows" "evaluation"
    run_step "ENABLE GEOIP LOCATION" function_enableGeoIpLocation
    run_step "CONFIGURE SELF-MONITORING" function_configureSelfMonitoring
    run_step "START ALL STREAMS" function_startAllStreams
    run_step "ENABLE GRAYLOG SIDECAR ON HOST" function_enableGraylogSidecar
    run_step "ADD SCRIPT FOLDER TO PATH" function_addScriptRepositoryToPathVariable
    run_step "CONFIGURE TEST SYSTEM" function_configureTestSystem

    run_step "DISPLAY CLUSTER INFORMATION" function_displayClusterId

    echo "[INFO] - NOW IT'S UP TO YOU PREPARING YOUR LOG SOURCES"

    # Hand over to the hourly post-installation task
    echo "${GRAYLOG_ADMIN_TOKEN}" | sudo tee "${GRAYLOG_TOKEN_FILE}" >/dev/null && sudo chmod 0600 "${GRAYLOG_TOKEN_FILE}" \
        || die "COULD NOT STORE THE ADMIN TOKEN"

    if [[ -f ${GRAYLOG_PATH}/scripts/Create-ConfigurationDump ]]
    then
        sudo install -m 0755 "${GRAYLOG_PATH}/scripts/Create-ConfigurationDump" /etc/cron.daily/ || fail "COULD NOT REGISTER THE DAILY CONFIGURATION DUMP"
    fi

    sudo install -m 0755 "${SCRIPT_PATH}" "${GRAYLOG_CRON_SCRIPT}" || die "COULD NOT REGISTER THE POST-INSTALLATION TASK"
    function_writeState "completed" || die "COULD NOT WRITE ${GRAYLOG_STATE_FILE}"
    INSTALL_PHASE=""

    function_removeScript

    log_info "BASE INSTALLATION SUCCESSFULLY FINISHED, WAITING FOR LICENSE"
}

###############################################################################
#
# Post-Installation Tasks (run hourly by cron until the licenses are in place)

function_finishPostInstallation () {
    function_writeState "finished" \
        || fail "COULD NOT MARK THE INSTALLATION AS FINISHED IN ${GRAYLOG_STATE_FILE}"

    if ! sudo rm -f "${GRAYLOG_TOKEN_FILE}"
    then
        fail "COULD NOT REMOVE ${GRAYLOG_TOKEN_FILE} - PLEASE DELETE IT MANUALLY (CONTAINS AN API TOKEN)"
    fi

    if ! sudo rm -f "${GRAYLOG_CRON_SCRIPT}"
    then
        fail "COULD NOT REMOVE ${GRAYLOG_CRON_SCRIPT} - PLEASE DELETE IT MANUALLY"
    fi
}

function_runPostInstallation () {
    local state=${1}

    # Never run twice at the same time
    exec 9>"${LOCK_FILE}" || die "COULD NOT OPEN ${LOCK_FILE}"
    if ! flock -n 9
    then
        log_info "POST-INSTALLATION ALREADY RUNNING"
        exit 0
    fi

    GRAYLOG_ADMIN_TOKEN=$(sudo cat "${GRAYLOG_TOKEN_FILE}" 2>/dev/null)
    if [[ -z ${GRAYLOG_ADMIN_TOKEN} ]]
    then
        log_error "ADMIN TOKEN ${GRAYLOG_TOKEN_FILE} MISSING, STOPPING POST-INSTALLATION"
        function_finishPostInstallation
        exit 1
    fi
    GL_AUTH="${GRAYLOG_ADMIN_TOKEN}:token"

    if [[ $(curl -s --noproxy '*' --max-time 10 "${GRAYLOG_API}/system/lbstatus" 2>/dev/null) != "ALIVE" ]]
    then
        log_warn "GRAYLOG IS NOT AVAILABLE, RETRYING WITH THE NEXT RUN"
        exit 0
    fi

    if ! gl_api GET /system >/dev/null
    then
        if [[ ${GL_LAST_STATUS} == "401" ]]
        then
            log_error "ADMIN TOKEN IS NO LONGER VALID (EXPIRED AFTER 14 DAYS?), STOPPING POST-INSTALLATION"
            function_finishPostInstallation
            exit 1
        fi
        exit 0
    fi

    if [[ ${state} == "completed" ]]
    then
        function_waitForLicense enterprise
        GRAYLOG_LICENSE_ENTERPRISE="true"

        log_info "RESTARTING GRAYLOG STACK FOR MAINTENANCE PURPOSES"
        function_restartGraylogContainer "graylog1 graylog2" || die "COULD NOT RESTART THE GRAYLOG CONTAINERS, RETRYING WITH THE NEXT RUN"
        function_checkSystemAvailability || die "GRAYLOG DID NOT COME BACK AFTER THE RESTART, RETRYING WITH THE NEXT RUN"

        # Advance the state before the (non-idempotent) configuration steps
        function_writeState "enterprise" || die "COULD NOT WRITE ${GRAYLOG_STATE_FILE}, RETRYING WITH THE NEXT RUN"
        state="enterprise"

        run_step "CREATE EVALUATION INPUTS" function_createInputs
        run_step "CONFIGURE EVALUATION SETUP" function_configureEvaluationSetup
        run_step "CONFIGURE ENTERPRISE FEATURES" function_configureEnterpriseFeatures

        log_info "GRAYLOG ENTERPRISE INSTALLATION FINISHED WITH ${#FAILED_ACTIONS[@]} FAILED ACTION(S)"
    fi

    if [[ ${state} == "enterprise" ]]
    then
        function_waitForLicense security
        GRAYLOG_LICENSE_SECURITY="true"

        run_step "CONFIGURE SECURITY FEATURES" function_configureSecurityFeatures
        run_step "CONFIGURE SECURITY ALERTS" function_configureSecurityAlerts

        log_info "GRAYLOG SECURITY INSTALLATION FINISHED WITH ${#FAILED_ACTIONS[@]} FAILED ACTION(S)"

        run_step "REMOVE TEMPORARY ADMIN TOKEN" function_removeAdminToken
        function_finishPostInstallation

        log_info "GRAYLOG INSTALLATION COMPLETELY FINISHED WITH ${#FAILED_ACTIONS[@]} FAILED ACTION(S)"
    fi
}

###############################################################################
#
# Main

INSTALLATION_STATE=$(cat "${GRAYLOG_STATE_FILE}" 2>/dev/null)

case "${INSTALLATION_STATE}" in
    "")
        function_runInstallation
        ;;
    completed|enterprise)
        function_runPostInstallation "${INSTALLATION_STATE}"
        ;;
    finished)
        echo "[INFO] - GRAYLOG IS ALREADY INSTALLED ON THIS SYSTEM, NOTHING TO DO"
        ;;
    *)
        # "started" (or anything unknown): a previous installation did not finish
        function_restoreSystem
        ;;
esac

exit 0
