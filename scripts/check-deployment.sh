#!/bin/bash
# check-deployment.sh
# Check deployment status with detailed rollout information

set -e

ENVIRONMENT=${1:-staging}
CONFIG_FILE="infrastructure/aws-config-$ENVIRONMENT.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file not found"
    exit 1
fi

AWS_REGION=$(jq -r '.region' "$CONFIG_FILE")
CLUSTER_NAME=$(jq -r '.resources.ecs.cluster' "$CONFIG_FILE")
SERVICE_NAME=$(jq -r '.resources.ecs.service' "$CONFIG_FILE")

echo "Checking deployment status for $SERVICE_NAME in $CLUSTER_NAME..."

# Get service details
SERVICE_INFO=$(aws ecs describe-services \
    --cluster $CLUSTER_NAME \
    --services $SERVICE_NAME \
    --region $AWS_REGION \
    --query 'services[0]')

# Extract deployment info
DEPLOYMENTS=$(echo $SERVICE_INFO | jq -r '.deployments[] | "\(.status) - \(.taskDefinition) (Desired: \(.desiredCount), Running: \(.runningCount), Pending: \(.pendingCount))"')

echo "Deployments:"
echo "$DEPLOYMENTS"

# Check if any deployment is in progress
IN_PROGRESS=$(echo $SERVICE_INFO | jq -r '.deployments[] | select(.status == "PRIMARY") | .runningCount == .desiredCount')

if [ "$IN_PROGRESS" = "true" ]; then
    echo "✅ Deployment completed successfully!"
    exit 0
else
    echo "⚠️ Deployment still in progress or issues found"
    
    # Get task failures if any
    FAILURES=$(aws ecs describe-services \
        --cluster $CLUSTER_NAME \
        --services $SERVICE_NAME \
        --region $AWS_REGION \
        --query 'services[0].events[?contains(message, `failed`) || contains(message, `error`) || contains(message, `unhealthy`)] | [0:5]')
    
    if [ "$FAILURES" != "[]" ]; then
        echo "Recent failures:"
        echo $FAILURES | jq -r '.[] | "\(.createdAt): \(.message)"'
    fi
    
    exit 1
fi