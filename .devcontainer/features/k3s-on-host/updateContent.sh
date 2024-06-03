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

# Source our utilities script
source "/k3s-on-host/utils.sh" $@

exit_code=${PIPESTATUS[0]}

if [[ $exit_code -gt 0 ]]; then
    echo "Failed to source utils.  Exit code: $exit_code"
    return 1
fi

############################################################
# Deploy container to interact with the host
############################################################
function host_interface_setup() {

    # Check if docker is install and if not, error our the container build
    run_a_script "command -v docker" has_docker --ignore_error
    if [[ -z "${has_docker}" ]]; then
        exit_with_error "Docker is not in the devcontainer.  Please add the docker feature 'ghcr.io/devcontainers/features/docker-outside-of-docker' to your devcontainer.json / features and rebuild the container."
    fi

    # Check if the container is running
    run_a_script "docker ps --all --filter \"name=$HOST_INTERFACE_CONTAINER\" --format \"{{.State}}\"" host_interface_status --disable_log --ignore_error

    if [[ "${host_interface_status}" == "exited" ]]; then
        debug_log "Removing stopped container $HOST_INTERFACE_CONTAINER..."
        run_a_script "docker rm $HOST_INTERFACE_CONTAINER" --disable_log
    fi

    if [[ "${host_interface_status}" == "running" ]]; then
        info_log "Container $HOST_INTERFACE_CONTAINER is already running."
        return
    fi

    info_log "Starting container $HOST_INTERFACE_CONTAINER to interact with the host..."

    run_a_script "docker run \
        --quiet \
        --privileged \
        --detach \
        --tty \
        --name $HOST_INTERFACE_CONTAINER \
        --net=host --pid=host --ipc=host \
        --volume /:/host \
        $HOST_INTERFACE_CONTAINER_BASE \
        chroot /host \
        bash --login -c 'while sleep 1000; do :; done'" --disable_log
}


# Checks if packages are installed and installs them if not
function check_packages() {
    if ! dpkg -s "$@" > /dev/null 2>&1; then
        run_a_script "apt-get update && apt-get -y install --no-install-recommends $@"
    fi
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

    if [[ ! -f "/host_var/tmp/k3s-on-host/k3s_install.sh" ]]; then
        debug_log "Downloading k3s install script..."
        run_a_script "curl --silent --fail --create-dirs --output /host_var/tmp/k3s-on-host/k3s_install.sh -L https://get.k3s.io"
    fi

    if [[ "${USE_CRI_DOCKERD}"==true ]]; then
        debug_log "Adding cri-dockerd to k3s install command..."
        k3s_extra_commands="${k3s_extra_commands} --docker"
    fi

    run_a_script "chmod +x /host_var/tmp/k3s-on-host/k3s_install.sh" --disable_log

    info_log "Installing k3s on host..."
    run_a_script_on_host "/var/tmp/k3s-on-host/k3s_install.sh ${k3s_extra_commands}" --env INSTALL_K3S_VERSION=${K3S_VERSION} --env INSTALL_K3S_SYMLINK=force
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

    debug_log "Calculating external ip..."
    run_a_script_on_host "ip route get 8.8.8.8" host_ip
    host_ip=${host_ip#*src }
    host_ip=${host_ip%% *}

    debug_log "...external ip: '${host_ip}'"

    run_a_script_on_host "kubectl config view --flatten=true" kubeconfig --disable_log

    kubeconfig="${kubeconfig/127.0.0.1/${host_ip}}"

    run_a_script "tee $KUBECONFIG > /dev/null << UPDATE_END
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

    run_a_script "grep 'export KUBECONFIG' ${HOME}/.bashrc" grep_results --ignore_error

    if [[ -z "${grep_results}" ]]; then
    info_log "...adding 'export KUBECONFIG=${KUBECONFIG}' to ${HOME}/.bashrc"
        run_a_script "tee -a ${HOME}/.bashrc > /dev/null << UPDATE_END
export KUBECONFIG=$KUBECONFIG
UPDATE_END"
    fi


    info_log "...successfully added 'export KUBECONFIG' to '${HOME}/.bashrc'"

    info_log "FINISHED: ${FUNCNAME[0]}"
}


function main() {
    reset_log
    host_interface_setup
    check_packages apt-transport-https curl jq yq
    install_k3s
    install_kubectl
    gen_kubeconfig_for_devcontainer
    check_kubeconfig_in_bashrc

}


main