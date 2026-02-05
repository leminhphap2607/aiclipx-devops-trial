#!/bin/bash
# setup-aws-fixed.sh - Fixed version

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

AWS_REGION="ap-southeast-1"
ENVIRONMENT=${1:-staging}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Setting up AWS for $ENVIRONMENT..."

# 1. Create ECR
echo "Creating ECR repository..."
aws ecr create-repository \
  --repository-name aiclipx-app \
  --region $AWS_REGION 2>/dev/null || echo "ECR repository already exists"

# 2. Create ECS cluster
CLUSTER_NAME="aiclipx-$ENVIRONMENT"
echo "Creating ECS cluster: $CLUSTER_NAME..."
aws ecs create-cluster \
  --cluster-name $CLUSTER_NAME \
  --region $AWS_REGION \
  --settings name=containerInsights,value=enabled 2>/dev/null || echo "ECS cluster already exists"

# 3. Create CloudWatch log group
echo "Creating CloudWatch log group..."
aws logs create-log-group \
  --log-group-name "/ecs/aiclipx" \
  --region $AWS_REGION 2>/dev/null || echo "Log group already exists"

# 4. Generate config file
cat > infrastructure/aws-config-$ENVIRONMENT.json << EOF
{
  "environment": "$ENVIRONMENT",
  "account_id": "$ACCOUNT_ID",
  "region": "$AWS_REGION",
  "resources": {
    "ecr": {
      "repository": "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/aiclipx-app"
    },
    "ecs": {
      "cluster": "$CLUSTER_NAME",
      "service": "aiclipx-service"
    }
  }
}
EOF

echo -e "${GREEN}Setup completed!${NC}"
echo ""
echo "Add these GitHub Secrets:"
echo "AWS_ROLE_ARN: arn:aws:iam::$ACCOUNT_ID:role/GitHubActions-ECS-Deploy"
echo "AWS_REGION: $AWS_REGION"
echo "ECR_REGISTRY: $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/aiclipx-app"