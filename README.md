# k3s-on-host

A devcontainer feature that will install and configure a kubernetes cluster (k3s) on the host machine.  The cluster can be accessed from any devcontainer via standard kubectl commands.  Once finished, the cluster can be accessed from within the cluster like so:

```bash
$ kubectl get pods -A
NAMESPACE     NAME                                      READY   STATUS      RESTARTS   AGE
kube-system   coredns-576bfc4dc7-r76cs                  1/1     Running     0          101m
kube-system   local-path-provisioner-75bb9ff978-hbxsq   1/1     Running     0          101m
kube-system   helm-install-traefik-crd-rtnrs            0/1     Completed   0          101m
kube-system   svclb-traefik-c6687f4a-fwdhl              2/2     Running     0          101m
kube-system   helm-install-traefik-qtddd                0/1     Completed   1          101m
kube-system   traefik-5fb479b77-k299x                   1/1     Running     0          101m
kube-system   metrics-server-557ff575fb-6t882           1/1     Running     0          101m
```

## Example Usage

```json
"features": {
    "ghcr.io/microsoft/k3s-on-host":{
        "k3sVersion": "latest",
        "criDockerd": "true",
        "cluster_enabled": "true"
    }
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| k3sVersion | Select or enter the k3s version | string | latest |
| criDockerd | Deploy k3s with the cri-dockerd configured  | boolean | true |
| cluster_enabled | Disable provisioning of the cluster.  This is useful in CI/CD scenarios that reference this devcontainer feature, but doesn't always need the kubernetes cluster deployed.  | boolean | true |

## Build and Deploying

This devcontainer feature can be built and deployed using the devcontainer CLI.

### Install devcontainer CLI
```bash
sudo apt install npm
sudo npm cache clean -f
sudo npm install -g n
sudo n stable
sudo npm install -g @devcontainers/cli
```

### Build devcontainer feature
```bash
REGISTRY=ghcr.io/microsoft
VERSION=latest

# No other changes needed below this line
NAMESPACE=devcontainers/features
FEATURE=k3s-on-host
ARTIFACT_PATH=./output/devcontainer-feature-k3s-on-host.tgz

# Validate the output directory exists and clean it out if there is content already present
mkdir -p "./output"
rm ./output/*

# Build the devcontaienr feature
devcontainer features package --force-clean-output-folder ./.devcontainer/features --output-folder ./output

# Push the devcontainer feature tarball to the registry
oras push ${REGISTRY}/${NAMESPACE}/${FEATURE}:${VERSION} \
    --config /dev/null:application/vnd.devcontainers \
    --annotation org.opencontainers.image.source=https://github.com/microsoft/devcontainer-feature-k3s \
            ${ARTIFACT_PATH}:application/vnd.devcontainers.layer.v1+tar


```

## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft
trademarks or logos is subject to and must follow
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.

