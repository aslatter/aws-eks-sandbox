#!/usr/bin/bash

set -eu

# Drop everything from k8s terraform state (we're not going
# to run destroy on it).
K8S_STATE="$(terraform -chdir=k8s state list)"
if [ -n "$K8S_STATE" ]; then
    terraform -chdir=k8s state rm $K8S_STATE
fi

# Manual cleanup that TF can't do

# The goal is to cleanup the EC2 instances which
# are managed in-cluster which TF doesn't know about.
#
# First we delete the CRDs which manage the instances,
# so that we stop making more instances.
#
# Then we directly hit the AWS APIs to delete the instances.

if ! just -q kubeconfig; then
    # nothing to do if we never got a cluster
    exit 0
fi

kubectl delete --all nodepools.karpenter.sh || exit 0

REGION=$(terraform -chdir=eks output -json info | jq -r .region)
DEPLOYMENT_ID=$(terraform -chdir=eks output -json info | jq -r .resourceGroup.name)

# TODO - verify inputs

INSTANCE_IDS=$(aws ec2 describe-instances \
    --region "$REGION" \
    --filters "Name=tag:group,Values=$DEPLOYMENT_ID" \
    --query "Reservations[*].Instances[*].InstanceId" \
    --output text)

if [ -n "$INSTANCE_IDS" ]; then
    echo "Found instance to terminate: $INSTANCE_IDS"
    aws ec2 terminate-instances --no-cli-pager --region "$REGION" --instance-ids $INSTANCE_IDS
fi
