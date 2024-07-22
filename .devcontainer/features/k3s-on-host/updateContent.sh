#!/usr/bin/env bash
#-------------------------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See https://go.microsoft.com/fwlink/?linkid=2090316 for license information.
#-------------------------------------------------------------------------------------------------------------
#
# Docs: https://github.com/microsoft/devcontainer-feature-k3s/README.md

export DEBIAN_FRONTEND=noninteractive

# Source /etc/os-release to get OS info
source /etc/os-release

# Source the .env file so we can pull the options set by the user
source /devfeature/k3s-on-host/.env

LOG_DIR="/var/log/devfeature/k3s-on-host"
SCRIPT_NAME=$(basename "$0")


exit_code=${PIPESTATUS[0]}

if [[ $exit_code -gt 0 ]]; then
    echo "Failed to source utils.  Exit code: $exit_code"
    return 1
fi


############################################################
# Helper function to run a script on the host via the host_interface container
# args
# position 1     : the command to run.  i.e. "docker container ls"
# position 2     : the variable to return the results of the script to for further processing
# --ignore_error : allow the script to continue even if the return code is not 0
# --disable_log  : prevent the output from writing to the log and screen
############################################################
function run_a_script_on_host() {
    local timestamp=$(date "+%Y%m%d_%H%M%S")
    if [[ "$#" -eq 0 ]]; then
        exit_with_error "Missing run script to execute.  Please use function like run_a_script 'ls /'"
    fi

    local run_script="$1"
    local  __returnVar=$2
    RETURN_CODE=""
    # We're passing flags and not a return value.  Reset the return variable here
    if [[ "${__returnVar:0:2}" == "--" ]]; then
        __returnVar=""
    fi

    local log_enabled=true
    local ignore_error=false
    local env_vars=""
    local returnResult=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --ignore_error)
                ignore_error=true
                ;;
            --disable_log)
                log_enabled=false
                ;;
            --env)
                shift
                env_vars="${env_vars} --env $1"
                ;;
        esac
        shift
    done

    local run_cmd

    run_cmd="docker run \
        --quiet \
        --privileged \
        --tty \
        --rm \
        --cap-add=SYS_CHROOT \
        --name $HOST_INTERFACE_CONTAINER \
        --net=host --pid=host --ipc=host \
        --volume /:/host \
        $HOST_INTERFACE_CONTAINER_BASE \
        chroot /host bash --login -c \"${run_script}\""


    if [[ "${log_enabled}" == true ]]; then
        trace_log "Running '${run_cmd}'..."
    fi

    returnResult=$(eval "${run_cmd}" )

    sub_exit_code=${PIPESTATUS[0]}
    RETURN_CODE=${sub_exit_code}
    if [[ -n ${__returnVar} ]]; then
        eval $__returnVar="'$returnResult'"
    fi

    if [[ "${log_enabled}" == true ]]; then
        trace_log "...'${run_cmd}' Exit code: ${sub_exit_code}"
        trace_log "...'${run_cmd}' Result: ${returnResult}"
    fi

    if [[ "${ignore_error}" == true ]]; then
        return
    fi

    if [[ $sub_exit_code -gt 0 ]]; then
        exit_with_error "Script failed.  Received return code of '${sub_exit_code}'.  Command ran: '${run_script}'.  See previous errors and retry"
    fi
}


############################################################
# Helper function to run a script
# args
# position 1     : the command to run.  i.e. "docker container ls"
# position 2     : the variable to return the results of the script to for further processing
# --ignore_error : allow the script to continue even if the return code is not 0
# --disable_log  : prevent the output from writing to the log and screen
############################################################
function run_a_script() {
    local timestamp=$(date "+%Y%m%d_%H%M%S")
    if [[ "$#" -eq 0 ]]; then
        exit_with_error "Missing run script to execute.  Please use function like run_a_script 'ls /'"
    fi

    local run_script="$1"
    local  __returnVar=$2
    RETURN_CODE=""
    # We're passing flags and not a return value.  Reset the return variable here
    if [[ "${__returnVar:0:2}" == "--" ]]; then
        __returnVar=""
    fi

    local log_enabled=true
    local ignore_error=false
    local run_in_background=false
    local returnResult=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --ignore_error)
                ignore_error=true
                ;;
            --disable_log)
                log_enabled=false
                ;;
        esac
        shift
    done

    local run_cmd

    run_cmd="${run_script}"


    if [[ "${log_enabled}" == true ]]; then
        trace_log "Running '${run_cmd}'..."
    fi


    returnResult=$(eval "${run_cmd}" )

    sub_exit_code=${PIPESTATUS[0]}
    RETURN_CODE=${sub_exit_code}
    if [[ -n ${__returnVar} ]]; then
        eval $__returnVar="'$returnResult'"
    fi

    if [[ "${log_enabled}" == true ]]; then
        trace_log "...'${run_cmd}' Exit code: ${sub_exit_code}"
        trace_log "...'${run_cmd}' Result: ${returnResult}"
    fi

    if [[ "${ignore_error}" == true ]]; then
        return
    fi

    if [[ $sub_exit_code -gt 0 ]]; then
        exit_with_error "Script failed.  Received return code of '${sub_exit_code}'.  Command ran: '${run_script}'.  See previous errors and retry"
    fi
}

############################################################
# Pretty writes a parameter to the log file
############################################################
function write_parameter_to_log() {
    local parameter=$1
    local parameter_value=${!1}
    max_key_length=40

    parameter_value="${parameter_value// /}" # remove blank spaces from value
    padding=$((max_key_length - ${#parameter}))
    spaces=$(printf "%-${padding}s" " ")
    info_log "${parameter}:${spaces}${parameter_value}"
}

############################################################
# Reset the log file by renaming it with a timestamp and
# creating a new empty log file
############################################################
function reset_log() {
    local timestamp=$(date "+%Y%m%d_%H%M%S")
    local logFile="${SCRIPT_NAME}.log"

    run_a_script "mkdir -p ${LOG_DIR}" --disable_log

    if [[ -f "${LOG_DIR}/${logFile}" ]]; then
        run_a_script "mv ${LOG_DIR}/${logFile} ${LOG_DIR}/${logFile}.${timestamp}" --disable_log
    fi
    run_a_script "touch ${LOG_DIR}/${logFile}" --disable_log
    run_a_script "chmod u=rw,g=rw,o=rw ${LOG_DIR}/${logFile}" --disable_log

    LOG_FILE="${LOG_DIR}/${logFile}"
}

############################################################
# Log a message to both stdout and the log file with a
# specified log level
############################################################
function log() {
    # log informational messages to stdout
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local log_entry="${1}"
    local received_log_level="INFO"
    local full_log_entry=""
    local log_raw=false

    if [[ -z ${log_entry} ]]; then
        return
    fi

    local configured_log_level=0
    case ${LOG_LEVEL^^} in
        ERROR)
            configured_log_level=4
            ;;
        WARN)
            configured_log_level=3
            ;;
        INFO)
            configured_log_level=2
            ;;
        DEBUG)
            configured_log_level=1
            ;;
        *)
            configured_log_level=0
            ;;
    esac

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --info)
                received_log_level="INFO"
                received_log_level_int=2
                ;;
            --debug)
                received_log_level="DEBUG"
                received_log_level_int=1
                ;;
            --warn)
                received_log_level="WARN"
                received_log_level_int=3
                ;;
            --error)
                received_log_level="ERROR"
                received_log_level_int=4
                ;;
            --trace)
                received_log_level="TRACE"
                received_log_level_int=0
                ;;
            --raw)
                log_raw=true
                ;;
        esac
        shift
    done

    if [[ ${log_raw} == false ]]; then
        full_log_entry="[${SCRIPT_NAME}] [${received_log_level}] ${timestamp}: ${log_entry}"
    else
        full_log_entry="${log_entry}"
    fi

    # Our log level isn't high enough - don't write it to the screen
    if [[ ${received_log_level_int} -lt ${configured_log_level} ]]; then
        return
    fi


    if [[ -n "${LOG_FILE}" ]]; then
        echo "${full_log_entry}" | tee -a "${LOG_FILE}"
    fi
}

# Log an informational message to stdout and the log file
function info_log() {
    log "${1}" --info
}

# Log a trace message to stdout and the log file
function trace_log() {
    log "${1}" --trace
}

# Log an debug message to stdout and the log file
function debug_log() {
    log "${1}" --debug
}

# Log an warning message to stdout and the log file
function warn_log() {
    log "${1}" --warn
}

# Log an error message to stdout and the log file
function error_log() {
    log "${1}" --error
}

# Log a critical error and exit the script with a non-zero return code
function exit_with_error() {
    # log a message to stderr and exit 1
    error_log "${1}"
    exit 1
}

############################################################
# Deploy container to interact with the host
############################################################
function host_interface_setup() {

    # Check if docker is install and if not, error our the container build
    run_a_script "command -v docker" has_docker --ignore_error
    if [[ -z "${has_docker}" ]]; then
        exit_with_error "Docker is not in the devcontainer.  Please add the docker feature 'ghcr.io/devcontainers/features/docker-outside-of-docker' to your devcontainer.json / features and rebuild the container."
    fi

    run_a_script "docker pull $HOST_INTERFACE_CONTAINER_BASE"

}

############################################################
# Install k3s on the host if it's not already available
############################################################
function install_k3s() {

    info_log "Checking if k3s is install on host..."
    run_a_script_on_host "systemctl list-unit-files | grep '^k3s.service'" k3s_installed --ignore_error

    if [[ -n "${k3s_installed}" ]]; then
        info_log "...k3s is installed and activated"
        info_log "END: ${FUNCNAME[0]}"
        return 0
    fi


    local k3s_extra_commands="--write-kubeconfig-mode \"0644\""

    info_log "k3s is not installed on the host. Installing..."

    if [[ "${K3S_VERSION}" == "latest" ]]; then
        info_log "Fetching latest k3s version..."
        run_a_script "curl -sfL https://api.github.com/repos/rancher/k3s/releases/latest | jq -r '.tag_name'" K3S_VERSION
        info_log "Latest k3s version is ${K3S_VERSION}"
    fi

    if [[ ! -f "/host_var/tmp/devfeature/k3s-on-host/k3s_install.sh" ]]; then
        debug_log "Downloading k3s install script..."
        run_a_script "curl --silent --fail --create-dirs --output /host_var/tmp/devfeature/k3s-on-host/k3s_install.sh -L https://get.k3s.io"
    fi

    if [[ "${USE_CRI_DOCKERD}" == true ]]; then
        debug_log "Adding cri-dockerd to k3s install command..."
        k3s_extra_commands="${k3s_extra_commands} --docker"
    fi

    run_a_script "chmod +x /host_var/tmp/devfeature/k3s-on-host/k3s_install.sh" --disable_log

    info_log "Installing k3s on host..."
    run_a_script_on_host "/var/tmp/devfeature/k3s-on-host/k3s_install.sh ${k3s_extra_commands}" --env INSTALL_K3S_VERSION=${K3S_VERSION} --env INSTALL_K3S_SYMLINK=force
}


############################################################
# Install kubectl within the devcontainer by copying it from the host
############################################################
function install_kubectl() {
    info_log "Querying for kubectl version on host..."
    # Query the host for the kubectl version being used
    run_a_script_on_host "kubectl version --client --output='json'" kubectl_version

    # Reduce it down to the git version
    run_a_script "jq -r '.clientVersion.gitVersion'  <<< \${kubectl_version}" kubectl_version

    # k3s will have a '+k3sX' at the end of the version.  We need to remove that
    kubectl_version=${kubectl_version%%+*}

    info_log "Calcualted kubectl version: ${kubectl_version}"

    if [[ -z "${kubectl_version}" ]]; then
        exit_with_error "Unable to calculate kubectl version."
    fi

    # Download kubectl and put it in bin
    local download_uri="https://dl.k8s.io/release/${kubectl_version}/bin/linux/${ARCHITECTURE}/kubectl"
    local dest_file="/usr/local/bin/kubectl"

    run_a_script "mkdir -p /usr/local/bin" --disable_log

    trace_log "...downloading '${download_uri}' to '${dest_file}'..."
    run_a_script "curl --silent --fail --create-dirs --output ${dest_file} -L ${download_uri}"
    trace_log "...successfully downloaded '${download_uri}' to '${dest_file}'."

    run_a_script "chmod +x ${dest_file}"
    run_a_script "chmod 755 ${dest_file}"


}

############################################################
# Generate the k3s.devcontainer.yaml so we can access the cluster from within the devcontainer
############################################################
function gen_kubeconfig_for_devcontainer() {

    info_log "Generating '$KUBECONFIG'..."

    [[ -f "${KUBECONFIG}" ]] && run_a_script "rm -f ${KUBECONFIG}"

    # Calculate the external ip of the host by checking the routes used to get to the internet
    debug_log "Calculating external ip..."
    run_a_script_on_host "ip route get 8.8.8.8" host_ip
    host_ip=${host_ip#*src }
    host_ip=${host_ip%% *}

    debug_log "...external ip: '${host_ip}'"

    run_a_script_on_host "kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml config view --flatten=true" kubeconfig --disable_log

    # Update kubeconfig to use the external ip of the host instead of the default 127.0.0.1
    kubeconfig="${kubeconfig/127.0.0.1/${host_ip}}"

    if [[ -n "${KUBECONFIG}" ]] && [[ "${KUBECONFIG}" != "/etc/rancher/k3s/k3s.yaml" ]]; then
        debug_log "Detected custom KUBECONFIG.  Writing to custom location: '${KUBECONFIG}'"
        kubeconfigDir="$(dirname "${KUBECONFIG}")"
        [[ ! -d "${kubeconfigDir}" ]] && run_a_script "mkdir -p ${kubeconfigDir}" --disable_log

        run_a_script "tee $KUBECONFIG > /dev/null << UPDATE_END
${kubeconfig}
UPDATE_END" --disable_log

    fi

    # Write the local kubeconfig to the default location in the devcontainer
    [[ ! -d "/etc/rancher/k3s" ]] && run_a_script "mkdir -p /etc/rancher/k3s" --disable_log

    run_a_script "tee /etc/rancher/k3s/k3s.yaml > /dev/null << UPDATE_END
${kubeconfig}
UPDATE_END" --disable_log


    info_log "Generated '$KUBECONFIG'."
    info_log "END: ${FUNCNAME[0]}"

}



############################################################
# Adds KUBECONFIG to bashrc
############################################################
function check_kubeconfig_in_bashrc(){
    info_log "START: ${FUNCNAME[0]}"

    if [[ ! -f "${HOME}/.bashrc" ]]; then
        info_log "'${HOME}/.bashrc' not found.  Unable to update config"
        info_log "END: ${FUNCNAME[0]}"
        return
    fi

    info_log "Checking '${HOME}/.bashrc' for 'export KUBECONFIG'..."

    # Grep the .bashrc to see if the KUBECONFIG is already set
    run_a_script "grep 'export KUBECONFIG' ${HOME}/.bashrc" grep_results --ignore_error

    # If the grep results are empty, then add the export KUBECONFIG to the .bashrc
    if [[ -z "${grep_results}" ]]; then
        info_log "...adding 'export KUBECONFIG=${KUBECONFIG}' to ${HOME}/.bashrc"
        run_a_script "tee -a ${HOME}/.bashrc > /dev/null << UPDATE_END
export KUBECONFIG=$KUBECONFIG
UPDATE_END"
        info_log "...successfully added 'export KUBECONFIG' to '${HOME}/.bashrc'"
    else
        info_log "...'export KUBECONFIG' already exists in '${HOME}/.bashrc'.  Nothing to do"
    fi

    info_log "FINISHED: ${FUNCNAME[0]}"
}


function main() {
    [[ "${CLUSTER_ENABLED}" == "false" ]] && return

    reset_log

    info_log "START: ${SCRIPT_NAME}"
    info_log "------------------------------------------"
    info_log "Config:"
    write_parameter_to_log PWD

    host_interface_setup

    run_a_script "apt-get update"
    run_a_script "apt-get -y install --no-install-recommends apt-transport-https curl jq"

    install_k3s
    install_kubectl
    gen_kubeconfig_for_devcontainer
    check_kubeconfig_in_bashrc

}

main