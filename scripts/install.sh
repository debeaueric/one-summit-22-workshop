#!/bin/bash
# SPDX-license-identifier: Apache-2.0
##############################################################################
# Copyright (c) 2022
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Apache License, Version 2.0
# which accompanies this distribution, and is available at
# http://www.apache.org/licenses/LICENSE-2.0
##############################################################################

set -o pipefail
set -o errexit
set -o nounset
if [[ ${DEBUG:-false} == "true" ]]; then
    set -o xtrace
    export PKG_DEBUG=true
fi

export PKG_KREW_PLUGINS_LIST=" "

declare -A clusters
clusters=(
    ["nephio"]="172.88.0.0/16,10.196.0.0/16,10.96.0.0/16"
    ["edge-cluster1"]="172.89.0.0/16,10.197.0.0/16,10.97.0.0/16"
    ["edge-cluster2"]="172.90.0.0/16,10.198.0.0/16,10.98.0.0/16"
)

# Install dependencies
# NOTE: Shorten link -> https://github.com/electrocucaracha/pkg-mgr_scripts
curl -fsSL http://bit.ly/install_pkg | PKG_COMMANDS_LIST="kind,docker,kubectl" bash

function deploy_k8s_cluster {
    local name="$1"
    local node_subnet="$2"
    local pod_subnet="$3"
    local svc_subnet="$4"

    newgrp docker <<EONG
if ! kind get clusters -q | grep -q $name; then
    docker network create --driver bridge --subnet=$node_subnet $name
    cat << EOF | KIND_EXPERIMENTAL_DOCKER_NETWORK=$name kind create cluster --name $name --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  kubeProxyMode: "ipvs"
  podSubnet: "$pod_subnet"
  serviceSubnet: "$svc_subnet"
nodes:
  - role: control-plane
  - role: worker
  - role: worker
  - role: worker
EOF
fi
EONG
}

for cluster in "${!clusters[@]}"; do
    read -r -a subnets <<<"${clusters[$cluster]//,/ }"
    deploy_k8s_cluster "$cluster" "${subnets[0]}" "${subnets[1]}" "${subnets[2]}"
done

# Wait for node readiness
for context in $(kubectl config get-contexts --no-headers --output name); do
    kubectl config use-context "$context"
    for node in $(kubectl get node -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'); do
        kubectl wait --for=condition=ready "node/$node" --timeout=3m
    done
done
