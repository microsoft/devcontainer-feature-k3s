#!/bin/bash
#
# Tests and validates the k3s-on-host devcontainer feature works as expected
#
# Example Usage:
#
#  "bash ./test/test.sh"

set -e

WORKING_DIR="$(git rev-parse --show-toplevel)"


###################################
#  Clean the current environment by removing k3s and purging docker
###################################
function reset_environment() {

    if [[ -f "/usr/local/bin/k3s-uninstall.sh" ]]; then
        echo "Uninstalling k3s"
        sudo /usr/local/bin/k3s-uninstall.sh
    fi

    if docker ps -q | grep -q .; then
        echo "Preexisting containers found.  Stopping and removing all containers"
        sudo docker stop $(docker ps -a -q)
    fi

    echo "Pruning docker"
    sudo docker system prune --all --volumes --force

}

###################################
#  Install the devcontainer cli so we can build the feature
###################################
function install_devcontainer_cli() {
    sudo apt install npm
    sudo npm cache clean -f
    sudo npm install -g n
    sudo n stable
    sudo npm install -g @devcontainers/cli
}

###################################
#  Deploy without cridockerd
###################################
function test_without_cridockerd() {
    sudo devcontainer build --workspace-folder "${WORKING_DIR}" --config "${WORKING_DIR}/test/without-cridockerd/devcontainer.json"
    sudo devcontainer up --workspace-folder "${WORKING_DIR}" --remove-existing-container \
                        --workspace-mount-consistency cached \
                        --id-label devcontainer.local_folder="${WORKING_DIR}" \
                        --id-label devcontainer.config_file="${WORKING_DIR}/test/without-cridockerd/devcontainer.json" \
                        --config "${WORKING_DIR}/test/without-cridockerd/devcontainer.json" \
                        --default-user-env-probe loginInteractiveShell \
                        --build-no-cache \
                        --remove-existing-container \
                        --mount type=volume,source=vscode,target=/vscode,external=true \
                        --update-remote-user-uid-default on \
                        --mount-workspace-git-root true

    sudo kubectl get namespace/default
}

###################################
#  Deploy with cridockerd
###################################
function test_with_cridockerd() {
    sudo devcontainer build --workspace-folder "${WORKING_DIR}" --config "${WORKING_DIR}/test/with-cridockerd/devcontainer.json"
    sudo devcontainer up --workspace-folder "${WORKING_DIR}" --remove-existing-container \
                        --workspace-mount-consistency cached \
                        --id-label devcontainer.local_folder="${WORKING_DIR}" \
                        --id-label devcontainer.config_file="${WORKING_DIR}/test/with-cridockerd/devcontainer.json" \
                        --config "${WORKING_DIR}/test/with-cridockerd/devcontainer.json" \
                        --default-user-env-probe loginInteractiveShell \
                        --build-no-cache \
                        --remove-existing-container \
                        --mount type=volume,source=vscode,target=/vscode,external=true \
                        --update-remote-user-uid-default on \
                        --mount-workspace-git-root true

    sudo kubectl get namespace/default
}

function main() {
    reset_environment
    install_devcontainer_cli

    test_without_cridockerd
    reset_environment
    test_with_cridockerd
    reset_environment

    echo "All tests passed"
}


main


set +e