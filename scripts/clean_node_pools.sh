#!/usr/bin/bash

set -eu

# instead of doing TF destroy on the k8s resources, we:
#  - drop all tf state
#  - delete the node-pool CRDs so that karpenter doesn't fight us
#    as we clean up
#  - manually delete EC2 instances
#
# This script does the first two steps

# Drop everything from k8s terraform state (we're not going
# to run destroy on it).

if ! terraform -chdir=k8s state list >/dev/null; then
    # nothing to do
    exit 0
fi

K8S_STATE="$(terraform -chdir=k8s state list)"
if [ -n "$K8S_STATE" ]; then
    terraform -chdir=k8s state rm $K8S_STATE
fi

if ! just -q kubeconfig; then
    # nothing to do if we never got a cluster
    exit 0
fi

kubectl delete --all nodepools.karpenter.sh || exit 0

REGION=$(terraform -chdir=eks output -json info | jq -r .region)
DEPLOYMENT_ID=$(terraform -chdir=eks output -json info | jq -r .resourceGroup.name)
