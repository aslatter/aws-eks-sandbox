#!/usr/bin/bash

set -eu

# clean up ec2 instance terraform doesn't know about

if ! terraform -chdir=eks output -json info; then
    exit 0
fi

REGION=$(terraform -chdir=eks output -json info | jq -r .region)
DEPLOYMENT_ID=$(terraform -chdir=eks output -json info | jq -r .resourceGroup.name)

# TODO - verify inputs

INSTANCE_IDS=$(aws ec2 describe-instances \
    --region "$REGION" \
    --filters "Name=tag:group,Values=$DEPLOYMENT_ID" \
    --filters "Name=operator.managed,Values=false" \
    --query "Reservations[*].Instances[*].InstanceId" \
    --output text)

if [ -n "$INSTANCE_IDS" ]; then
    echo "Found instance to terminate: $INSTANCE_IDS"
    aws ec2 terminate-instances --no-cli-pager --region "$REGION" --instance-ids $INSTANCE_IDS
fi
