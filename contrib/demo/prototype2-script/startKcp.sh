#!/usr/bin/env bash

# Copyright 2022 The KCP Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../.setupEnv
source "${DEMO_DIR}"/../.setupEnv
# shellcheck source=../.startUtils
source "${DEMOS_DIR}"/.startUtils
setupTraps "$0"

if ! command -v envoy &> /dev/null; then
    echo "envoy is required - please install and try again"
    exit 1
fi

CURRENT_DIR="$(pwd)"

KUBECONFIG=${KCP_DATA_DIR}/.kcp/admin.kubeconfig

"${DEMOS_DIR}"/startKcp.sh \
    --token-auth-file "${DEMO_DIR}"/kcp-tokens \
    --auto-publish-apis \
    --push-mode \
    --discovery-poll-interval 3s \
    --profiler-address localhost:6060 \
    --resources-to-sync ingresses.networking.k8s.io,deployments.apps,services \
    -v 2 &

wait_command "ls ${KUBECONFIG}"
echo "Waiting for KCP to be ready ..."
wait_command "kubectl --kubeconfig=${KUBECONFIG} get --raw /readyz"

echo ""
echo "Starting Ingress Controller"
"${KCP_DIR}"/bin/ingress-controller --kubeconfig="${KUBECONFIG}" --envoy-listener-port=8181 --envoy-xds-port=18000 &> "${CURRENT_DIR}"/ingress-controller.log &
INGRESS_CONTROLLER_PID=$!
echo "Ingress Controller started: ${INGRESS_CONTROLLER_PID}"

echo ""
echo "Starting envoy"
envoy --config-path "${KCP_DIR}"/build/kcp-ingress/utils/envoy/bootstrap.yaml &> "${CURRENT_DIR}"/envoy.log &
ENVOY_PID=$!
echo "Envoy started: ${ENVOY_PID}"

echo ""
echo "Starting Virtual Workspace"
"${KCP_DIR}"/bin/virtual-workspaces workspaces \
    --workspaces:kubeconfig "${KUBECONFIG}" \
    --authentication-kubeconfig "${KUBECONFIG}" \
    --tls-cert-file "${KCP_DATA_DIR}"/.kcp/apiserver.crt \
    --tls-private-key-file "${KCP_DATA_DIR}"/.kcp/apiserver.key \
    &> "${CURRENT_DIR}"/virtual-workspace.log &
SPLIT_PID=$!
echo "Virtual Workspace started: $SPLIT_PID"

touch "${KCP_DATA_DIR}/servers-ready"

echo ""
echo "Use ctrl-C to stop all components"
echo ""

wait