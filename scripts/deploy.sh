#!/bin/bash
# deploy.sh
# Manual deployment script for trials-devops branch

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
ENVIRONMENT="staging"
IMAGE_TAG="latest"
FORCE_DEPLOY=false
ROLLBACK=false
BRANCH_NAME="trials-devops"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -t|--tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        -f|--force)
            FORCE_DEPLOY=true
            shift
            ;;
        -r|--rollback)
            ROLLBACK=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -e, --environment    Environment (staging|production) [default: staging]"
            echo "  -t, --tag            Docker image tag [default: latest]"
            echo "  -f, --force          Force deployment without confirmation"
            echo "  -r, --rollback       Rollback to previous version"
            echo "  -h, --help           Show this help message"
            echo ""
            echo "Note: This script is configured for $BRANCH_NAME branch"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Validate environment
if [[ "$ENVIRONMENT" != "staging" && "$ENVIRONMENT" != "production" ]]; then
    echo -e "${RED}Error: Environment must be 'staging' or 'production'${NC}"
    exit 1
fi

# Load configuration
CONFIG_FILE="infrastructure/aws-config-$ENVIRONMENT.json"
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: Configuration file not found: $CONFIG_FILE${NC}"
    echo "Please run setup-aws.sh first"
    exit 1
fi

# Extract values from config
AWS_REGION=$(jq -r '.region' "$CONFIG_FILE")
CLUSTER_NAME=$(jq -r '.resources.ecs.cluster' "$CONFIG_FILE")
SERVICE_NAME=$(jq -r '.resources.ecs.service' "$CONFIG_FILE")
ECR_REPO=$(jq -r '.resources.ecr.repository' "$CONFIG_FILE")

# Confirm deployment
if [ "$FORCE_DEPLOY" = false ] && [ "$ROLLBACK" = false ]; then
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}Deployment Configuration${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo -e "Branch: ${BLUE}$BRANCH_NAME${NC}"
    echo -e "Environment: ${BLUE}$ENVIRONMENT${NC}"
    echo -e "Cluster: ${BLUE}$CLUSTER_NAME${NC}"
    echo -e "Service: ${BLUE}$SERVICE_NAME${NC}"
    echo -e "Image Tag: ${BLUE}$IMAGE_TAG${NC}"
    echo -e "Region: ${BLUE}$AWS_REGION${NC}"
    echo ""
    
    read -p "Continue with deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Deployment cancelled${NC}"
        exit 0
    fi
fi

# Deployment function
deploy_service() {
    local env=$1
    local tag=$2
    
    echo -e "${BLUE}Starting deployment to $env from $BRANCH_NAME branch...${NC}"
    
    # Get current task definition
    echo "Fetching current task definition..."
    TASK_DEF_ARN=$(aws ecs describe-services \
        --cluster $CLUSTER_NAME \
        --service $SERVICE_NAME \
        --region $AWS_REGION \
        --query 'services[0].taskDefinition' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$TASK_DEF_ARN" ]; then
        echo -e "${YELLOW}Service not found or not running. Creating new service...${NC}"
        # This would create a new service - for simplicity, we'll just update
        echo "Service creation not implemented in this script"
        exit 1
    fi
    
    # Update task definition with new image
    echo "Updating task definition..."
    TASK_DEF=$(aws ecs describe-task-definition \
        --task-definition $TASK_DEF_ARN \
        --region $AWS_REGION)
    
    # Create new task definition with updated image
    NEW_TASK_DEF=$(echo $TASK_DEF | jq '.taskDefinition')
    
    # Update image in container definitions
    UPDATED_DEFS=$(echo $NEW_TASK_DEF | jq ".containerDefinitions[0].image = \"$ECR_REPO:$tag\"")
    
    # Remove fields that can't be included in register-task-definition
    CLEAN_DEFS=$(echo $UPDATED_DEFS | jq 'del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)')
    
    # Create temporary file for task definition
    TMP_FILE=$(mktemp)
    echo $CLEAN_DEFS > $TMP_FILE
    
    # Register new task definition
    NEW_TASK_ARN=$(aws ecs register-task-definition \
        --cli-input-json file://$TMP_FILE \
        --region $AWS_REGION \
        --query 'taskDefinition.taskDefinitionArn' \
        --output text)
    
    rm $TMP_FILE
    
    echo -e "${GREEN}New task definition registered: $NEW_TASK_ARN${NC}"
    
    # Update ECS service
    echo "Updating ECS service..."
    aws ecs update-service \
        --cluster $CLUSTER_NAME \
        --service $SERVICE_NAME \
        --task-definition $NEW_TASK_ARN \
        --force-new-deployment \
        --region $AWS_REGION
    
    # Wait for deployment to complete
    echo "Waiting for deployment to stabilize..."
    aws ecs wait services-stable \
        --cluster $CLUSTER_NAME \
        --service $SERVICE_NAME \
        --region $AWS_REGION
    
    echo -e "${GREEN}✅ Deployment from $BRANCH_NAME completed successfully!${NC}"
}

# Rollback function
rollback_service() {
    local env=$1
    
    echo -e "${YELLOW}Starting rollback for $env from $BRANCH_NAME branch...${NC}"
    
    # Get previous task definition
    echo "Finding previous task definition..."
    TASK_DEFS=$(aws ecs describe-task-definition \
        --task-definition aiclipx-task \
        --region $AWS_REGION \
        --query 'taskDefinition.revision' \
        --output text)
    
    if [ -z "$TASK_DEFS" ]; then
        echo -e "${RED}No task definitions found${NC}"
        exit 1
    fi
    
    CURRENT_REV=$(echo $TASK_DEFS | tr ' ' '\n' | sort -nr | head -1)
    PREVIOUS_REV=$(echo $TASK_DEFS | tr ' ' '\n' | sort -nr | head -2 | tail -1)
    
    if [ -z "$PREVIOUS_REV" ]; then
        echo -e "${RED}No previous revision found${NC}"
        exit 1
    fi
    
    echo "Current revision: $CURRENT_REV"
    echo "Rolling back to revision: $PREVIOUS_REV"
    
    # Update service with previous task definition
    aws ecs update-service \
        --cluster $CLUSTER_NAME \
        --service $SERVICE_NAME \
        --task-definition "aiclipx-task:$PREVIOUS_REV" \
        --force-new-deployment \
        --region $AWS_REGION
    
    # Wait for rollback to complete
    echo "Waiting for rollback to complete..."
    aws ecs wait services-stable \
        --cluster $CLUSTER_NAME \
        --service $SERVICE_NAME \
        --region $AWS_REGION
    
    echo -e "${GREEN}✅ Rollback from $BRANCH_NAME completed successfully!${NC}"
}

# Main execution
if [ "$ROLLBACK" = true ]; then
    rollback_service $ENVIRONMENT
else
    deploy_service $ENVIRONMENT $IMAGE_TAG
fi

# Print service status
echo ""
echo -e "${BLUE}Service Status:${NC}"
aws ecs describe-services \
    --cluster $CLUSTER_NAME \
    --service $SERVICE_NAME \
    --region $AWS_REGION \
    --query 'services[0].[status, runningCount, desiredCount, deployments[0].updatedAt]' \
    --output text | awk '{print "Status: "$1"\nRunning: "$2"\nDesired: "$3"\nLast Updated: "$4}'