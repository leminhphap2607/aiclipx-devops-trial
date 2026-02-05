#!/bin/bash
# setup-aws.sh
# One-time AWS infrastructure setup script for trials-devops branch

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION="ap-southeast-1"
ENVIRONMENT=${1:-staging}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BRANCH_NAME="trials-devops"

# Validation
if [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}Error: Unable to get AWS account ID. Please configure AWS CLI first.${NC}"
    exit 1
fi

if [ "$ENVIRONMENT" != "staging" ] && [ "$ENVIRONMENT" != "production" ]; then
    echo -e "${RED}Error: Environment must be 'staging' or 'production'${NC}"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}AiClipX DevOps Trial - AWS Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Branch: ${YELLOW}$BRANCH_NAME${NC}"
echo -e "Environment: ${YELLOW}$ENVIRONMENT${NC}"
echo -e "AWS Account: ${YELLOW}$ACCOUNT_ID${NC}"
echo -e "AWS Region: ${YELLOW}$AWS_REGION${NC}"
echo ""

# Function to print section headers
section() {
    echo -e "\n${BLUE}[$1]${NC}"
}

# Function to check if command succeeded
check_status() {
    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}✓${NC} $2"
    else
        echo -e "  ${RED}✗${NC} Failed: $2"
        exit 1
    fi
}

# 1. Create IAM Roles
section "1. Creating IAM Roles for $BRANCH_NAME"

# Create GitHub Actions role
echo "  Creating GitHubActions-ECS-Deploy role..."
aws iam create-role \
    --role-name GitHubActions-ECS-Deploy \
    --assume-role-policy-document file://infrastructure/iam/github-actions-trust.json \
    --description "Allows GitHub Actions to deploy to ECS from $BRANCH_NAME branch" \
    --region $AWS_REGION 2>/dev/null || true

# Update trust policy with actual account ID and branch name
sed "s|ACCOUNT_ID_PLACEHOLDER|$ACCOUNT_ID|g" infrastructure/iam/github-actions-trust.json > /tmp/trust-policy.json
aws iam update-assume-role-policy \
    --role-name GitHubActions-ECS-Deploy \
    --policy-document file:///tmp/trust-policy.json \
    --region $AWS_REGION
check_status $? "Updated GitHub Actions role trust policy for $BRANCH_NAME"

# Attach policies to GitHub Actions role
echo "  Attaching policies to GitHub Actions role..."
aws iam attach-role-policy \
    --role-name GitHubActions-ECS-Deploy \
    --policy-arn arn:aws:iam::aws:policy/AmazonECS_FullAccess \
    --region $AWS_REGION

aws iam attach-role-policy \
    --role-name GitHubActions-ECS-Deploy \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess \
    --region $AWS_REGION

aws iam attach-role-policy \
    --role-name GitHubActions-ECS-Deploy \
    --policy-arn arn:aws:iam::aws:policy/CloudWatchFullAccess \
    --region $AWS_REGION
check_status $? "Attached policies to GitHub Actions role"

# Create ECS task execution role
echo "  Creating ECS task execution role..."
aws iam create-role \
    --role-name ecsTaskExecutionRole \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "ecs-tasks.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }' \
    --description "Allows ECS tasks to call AWS services" \
    --region $AWS_REGION 2>/dev/null || true

aws iam attach-role-policy \
    --role-name ecsTaskExecutionRole \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy \
    --region $AWS_REGION
check_status $? "Created ECS task execution role"

# Create ECS task role
echo "  Creating ECS task role..."
aws iam create-role \
    --role-name ecsTaskRole \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "ecs-tasks.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }' \
    --description "Allows ECS tasks to access AWS resources" \
    --region $AWS_REGION 2>/dev/null || true

aws iam attach-role-policy \
    --role-name ecsTaskRole \
    --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess \
    --region $AWS_REGION
check_status $? "Created ECS task role"

# 2. Create OIDC Provider
section "2. Setting up OIDC Provider for GitHub Actions"
echo "  Creating OIDC provider for $BRANCH_NAME..."
aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 \
    --region $AWS_REGION 2>/dev/null || true
check_status $? "OIDC provider configured"

# 3. Create ECR Repository
section "3. Creating ECR Repository"
echo "  Creating ECR repository: aiclipx-app..."
aws ecr create-repository \
    --repository-name aiclipx-app \
    --region $AWS_REGION \
    --image-scanning-configuration scanOnPush=true \
    --image-tag-mutability MUTABLE 2>/dev/null || true
check_status $? "ECR repository created"

# 4. Create ECS Cluster
section "4. Creating ECS Cluster"
CLUSTER_NAME="aiclipx-$ENVIRONMENT"
echo "  Creating ECS cluster: $CLUSTER_NAME..."
aws ecs create-cluster \
    --cluster-name $CLUSTER_NAME \
    --region $AWS_REGION \
    --capacity-providers FARGATE FARGATE_SPOT \
    --default-capacity-provider-strategy \
        capacityProvider=FARGATE,weight=1,base=1 \
        capacityProvider=FARGATE_SPOT,weight=0 \
    --settings name=containerInsights,value=enabled 2>/dev/null || true
check_status $? "ECS cluster created"

# 5. Create CloudWatch Log Group
section "5. Creating CloudWatch Log Group"
echo "  Creating CloudWatch log group: /ecs/aiclipx..."
aws logs create-log-group \
    --log-group-name "/ecs/aiclipx" \
    --region $AWS_REGION 2>/dev/null || true

# Set log retention policy (30 days)
aws logs put-retention-policy \
    --log-group-name "/ecs/aiclipx" \
    --retention-in-days 30 \
    --region $AWS_REGION
check_status $? "CloudWatch log group configured"

# 6. Create S3 Bucket for Configuration
section "6. Creating S3 Bucket"
BUCKET_NAME="aiclipx-$ENVIRONMENT-config-$ACCOUNT_ID"
echo "  Creating S3 bucket: $BUCKET_NAME..."
aws s3api create-bucket \
    --bucket $BUCKET_NAME \
    --region $AWS_REGION \
    --create-bucket-configuration LocationConstraint=$AWS_REGION 2>/dev/null || true
check_status $? "S3 bucket created"

# 7. Create SNS Topic for Alerts
section "7. Creating SNS Topic for Alerts"
echo "  Creating SNS topic: aiclipx-alerts..."
aws sns create-topic \
    --name aiclipx-alerts \
    --region $AWS_REGION 2>/dev/null || true

# Subscribe admin email (if provided)
if [ -n "$2" ]; then
    EMAIL=$2
    TOPIC_ARN=$(aws sns list-topics --region $AWS_REGION --query "Topics[?contains(TopicArn, 'aiclipx-alerts')].TopicArn" --output text)
    aws sns subscribe \
        --topic-arn $TOPIC_ARN \
        --protocol email \
        --notification-endpoint $EMAIL \
        --region $AWS_REGION
    echo -e "  ${YELLOW}Please check your email to confirm SNS subscription${NC}"
fi
check_status $? "SNS topic created"

# 8. Create Secrets in Secrets Manager
section "8. Creating Secrets in Secrets Manager"
echo "  Creating secret: aiclipx/api-key..."
aws secretsmanager create-secret \
    --name aiclipx/api-key \
    --description "API Key for AiClipX service" \
    --secret-string '{"API_KEY": "your-api-key-here"}' \
    --region $AWS_REGION 2>/dev/null || true

echo "  Creating secret: aiclipx/database-url..."
aws secretsmanager create-secret \
    --name aiclipx/database-url \
    --description "Database URL for AiClipX service" \
    --secret-string '{"DATABASE_URL": "postgresql://user:pass@localhost:5432/aiclipx"}' \
    --region $AWS_REGION 2>/dev/null || true
check_status $? "Secrets created"

# 9. Generate Configuration File
section "9. Generating Configuration File"
CONFIG_FILE="infrastructure/aws-config-$ENVIRONMENT.json"
cat > $CONFIG_FILE <<EOF
{
  "environment": "$ENVIRONMENT",
  "branch": "$BRANCH_NAME",
  "account_id": "$ACCOUNT_ID",
  "region": "$AWS_REGION",
  "resources": {
    "iam": {
      "github_actions_role": "arn:aws:iam::$ACCOUNT_ID:role/GitHubActions-ECS-Deploy",
      "ecs_task_execution_role": "arn:aws:iam::$ACCOUNT_ID:role/ecsTaskExecutionRole",
      "ecs_task_role": "arn:aws:iam::$ACCOUNT_ID:role/ecsTaskRole"
    },
    "ecr": {
      "repository": "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/aiclipx-app"
    },
    "ecs": {
      "cluster": "$CLUSTER_NAME",
      "service": "aiclipx-service"
    },
    "cloudwatch": {
      "log_group": "/ecs/aiclipx"
    },
    "s3": {
      "bucket": "$BUCKET_NAME"
    },
    "sns": {
      "topic": "arn:aws:sns:$AWS_REGION:$ACCOUNT_ID:aiclipx-alerts"
    }
  }
}
EOF

echo -e "  ${GREEN}Configuration saved to: $CONFIG_FILE${NC}"

# 10. Print Summary
section "SETUP COMPLETE for $BRANCH_NAME"
echo -e "${GREEN}✅ AWS infrastructure setup completed successfully!${NC}"
echo ""
echo -e "${YELLOW}Next steps for $BRANCH_NAME branch:${NC}"
echo -e "1. Push code to $BRANCH_NAME branch:"
echo -e "   ${BLUE}git checkout -b trials-devops${NC}"
echo -e "   ${BLUE}git add .${NC}"
echo -e "   ${BLUE}git commit -m 'Initial commit for trials-devops'${NC}"
echo -e "   ${BLUE}git push origin trials-devops${NC}"
echo ""
echo -e "2. Add these secrets to GitHub repository (Settings → Secrets → Actions):"
echo -e "   ${BLUE}AWS_ROLE_ARN${NC}: arn:aws:iam::$ACCOUNT_ID:role/GitHubActions-ECS-Deploy"
echo -e "   ${BLUE}AWS_REGION${NC}: $AWS_REGION"
echo -e "   ${BLUE}ECR_REGISTRY${NC}: $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/aiclipx-app"
echo ""
echo -e "3. Create GitHub environments:"
echo -e "   - ${BLUE}staging${NC}: No approval required"
echo -e "   - ${BLUE}production${NC}: Require 1 reviewer approval"
echo ""
echo -e "4. Add environment variables to each GitHub environment:"
echo -e "   For ${BLUE}$ENVIRONMENT${NC} environment:"
echo -e "   ${BLUE}ECS_CLUSTER${NC}: $CLUSTER_NAME"
echo -e "   ${BLUE}ECS_SERVICE${NC}: aiclipx-service"
echo ""
echo -e "${GREEN}🎉 Your DevOps pipeline for $BRANCH_NAME is ready!${NC}"
# Thêm phần này sau khi tạo ECS cluster

# Create ECS Service với Public IP (cho trial)
echo "Creating ECS service with public IP..."
aws ecs create-service \
    --cluster $CLUSTER_NAME \
    --service-name $SERVICE_NAME \
    --task-definition aiclipx-task \
    --desired-count 1 \
    --launch-type FARGATE \
    --platform-version LATEST \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_IDS],securityGroups=[$SECURITY_GROUP_ID],assignPublicIp=ENABLED}" \
    --region $AWS_REGION 2>/dev/null || echo "Service may already exist, skipping..."