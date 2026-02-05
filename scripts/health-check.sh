#!/bin/bash
# health-check.sh
# Health check and status script for trials-devops branch

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ENVIRONMENT=${1:-staging}
BRANCH_NAME="trials-devops"

# Validate environment
if [[ "$ENVIRONMENT" != "staging" && "$ENVIRONMENT" != "production" ]]; then
    echo -e "${RED}Error: Environment must be 'staging' or 'production'${NC}"
    exit 1
fi

# Load configuration
CONFIG_FILE="infrastructure/aws-config-$ENVIRONMENT.json"
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: Configuration file not found: $CONFIG_FILE${NC}"
    exit 1
fi

# Extract values
AWS_REGION=$(jq -r '.region' "$CONFIG_FILE")
CLUSTER_NAME=$(jq -r '.resources.ecs.cluster' "$CONFIG_FILE")
SERVICE_NAME=$(jq -r '.resources.ecs.service' "$CONFIG_FILE")
LOAD_BALANCER_NAME="aiclipx-alb"

echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Health Check - $ENVIRONMENT Environment${NC}"
echo -e "Branch: ${YELLOW}$BRANCH_NAME${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to check status with color
status_check() {
    local name=$1
    local command=$2
    local success_message=$3
    
    echo -n "Checking $name... "
    if eval $command >/dev/null 2>&1; then
        echo -e "${GREEN}✓ $success_message${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed${NC}"
        return 1
    fi
}

# 1. Check AWS CLI connectivity
status_check "AWS connectivity" \
    "aws sts get-caller-identity --query Account --output text" \
    "Connected to AWS"

# 2. Check ECS Cluster
status_check "ECS Cluster" \
    "aws ecs describe-clusters --clusters $CLUSTER_NAME --region $AWS_REGION --query 'clusters[0].status' --output text | grep -q ACTIVE" \
    "Cluster is active"

# 3. Check ECS Service
echo -n "Checking ECS Service... "
SERVICE_STATUS=$(aws ecs describe-services \
    --cluster $CLUSTER_NAME \
    --service $SERVICE_NAME \
    --region $AWS_REGION \
    --query 'services[0].status' \
    --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$SERVICE_STATUS" = "ACTIVE" ]; then
    echo -e "${GREEN}✓ Service is active${NC}"
    
    # Get service details
    SERVICE_DETAILS=$(aws ecs describe-services \
        --cluster $CLUSTER_NAME \
        --service $SERVICE_NAME \
        --region $AWS_REGION \
        --query 'services[0].[runningCount, desiredCount, deployments[0].status]' \
        --output text)
    
    RUNNING=$(echo $SERVICE_DETAILS | awk '{print $1}')
    DESIRED=$(echo $SERVICE_DETAILS | awk '{print $2}')
    DEPLOY_STATUS=$(echo $SERVICE_DETAILS | awk '{print $3}')
    
    echo "  Running tasks: $RUNNING / $DESIRED"
    echo "  Deployment status: $DEPLOY_STATUS"
    
    if [ "$RUNNING" -eq "$DESIRED" ]; then
        echo -e "  ${GREEN}✓ All tasks are running${NC}"
    else
        echo -e "  ${YELLOW}⚠ Some tasks are not running${NC}"
    fi
else
    echo -e "${RED}✗ Service is not active (Status: $SERVICE_STATUS)${NC}"
fi

# 4. Check ECS Tasks
echo -e "\n${BLUE}ECS Tasks:${NC}"
TASK_ARNS=$(aws ecs list-tasks \
    --cluster $CLUSTER_NAME \
    --service $SERVICE_NAME \
    --region $AWS_REGION \
    --query 'taskArns' \
    --output text)

if [ -n "$TASK_ARNS" ]; then
    TASK_COUNT=$(echo $TASK_ARNS | wc -w)
    echo "Found $TASK_COUNT task(s)"
    
    # Get task details
    for TASK_ARN in $TASK_ARNS; do
        TASK_DETAILS=$(aws ecs describe-tasks \
            --cluster $CLUSTER_NAME \
            --tasks $TASK_ARN \
            --region $AWS_REGION \
            --query 'tasks[0].[lastStatus, healthStatus, containers[0].lastStatus]' \
            --output text)
        
        STATUS=$(echo $TASK_DETAILS | awk '{print $1}')
        HEALTH=$(echo $TASK_DETAILS | awk '{print $2}')
        CONTAINER_STATUS=$(echo $TASK_DETAILS | awk '{print $3}')
        
        echo -n "  Task: $(echo $TASK_ARN | awk -F'/' '{print $NF}') - "
        
        if [ "$STATUS" = "RUNNING" ] && [ "$HEALTH" = "HEALTHY" ]; then
            echo -e "${GREEN}✓ Running & Healthy${NC}"
        elif [ "$STATUS" = "RUNNING" ]; then
            echo -e "${YELLOW}⚠ Running but health: $HEALTH${NC}"
        else
            echo -e "${RED}✗ Status: $STATUS${NC}"
        fi
    done
else
    echo -e "${YELLOW}No tasks found${NC}"
fi

# 5. Check CloudWatch Logs
echo -e "\n${BLUE}CloudWatch Logs:${NC}"
LOG_GROUP="/ecs/aiclipx"
LOG_STREAMS=$(aws logs describe-log-streams \
    --log-group-name $LOG_GROUP \
    --region $AWS_REGION \
    --order-by LastEventTime \
    --descending \
    --max-items 1 \
    --query 'logStreams[0].logStreamName' \
    --output text 2>/dev/null || echo "NONE")

if [ "$LOG_STREAMS" != "NONE" ] && [ "$LOG_STREAMS" != "None" ]; then
    echo "Latest log stream: $LOG_STREAMS"
    
    # Get recent logs
    RECENT_LOGS=$(aws logs get-log-events \
        --log-group-name $LOG_GROUP \
        --log-stream-name "$LOG_STREAMS" \
        --region $AWS_REGION \
        --limit 5 \
        --query 'events[*].message' \
        --output text 2>/dev/null || echo "No logs found")
    
    if [ -n "$RECENT_LOGS" ]; then
        echo "Recent logs:"
        echo "$RECENT_LOGS" | while read -r line; do
            echo "  $line"
        done
    fi
else
    echo -e "${YELLOW}No log streams found${NC}"
fi

# 6. Check Load Balancer (if exists)
echo -e "\n${BLUE}Load Balancer:${NC}"
LB_ARN=$(aws elbv2 describe-load-balancers \
    --region $AWS_REGION \
    --query "LoadBalancers[?contains(LoadBalancerName, '$LOAD_BALANCER_NAME')].LoadBalancerArn" \
    --output text 2>/dev/null || echo "")

if [ -n "$LB_ARN" ]; then
    echo "Load Balancer found: $(echo $LB_ARN | awk -F'/' '{print $2}')"
    
    # Get target group
    TG_ARN=$(aws elbv2 describe-target-groups \
        --load-balancer-arn $LB_ARN \
        --region $AWS_REGION \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$TG_ARN" ]; then
        # Check target health
        HEALTH=$(aws elbv2 describe-target-health \
            --target-group-arn $TG_ARN \
            --region $AWS_REGION \
            --query 'TargetHealthDescriptions[0].TargetHealth.State' \
            --output text 2>/dev/null || echo "UNKNOWN")
        
        echo "Target health: $HEALTH"
        
        if [ "$HEALTH" = "healthy" ]; then
            echo -e "${GREEN}✓ Load balancer targets are healthy${NC}"
        else
            echo -e "${YELLOW}⚠ Load balancer target health: $HEALTH${NC}"
        fi
    fi
else
    echo -e "${YELLOW}Load balancer not found${NC}"
fi

# 7. Check CloudWatch Alarms
echo -e "\n${BLUE}CloudWatch Alarms:${NC}"
ALARMS=$(aws cloudwatch describe-alarms \
    --alarm-name-prefix "aiclipx" \
    --region $AWS_REGION \
    --query 'MetricAlarms[?StateValue!=`OK`].[AlarmName,StateValue]' \
    --output text 2>/dev/null || echo "")

if [ -n "$ALARMS" ]; then
    echo -e "${YELLOW}⚠ Active alarms found:${NC}"
    echo "$ALARMS" | while read -r name state; do
        echo "  $name - $state"
    done
else
    echo -e "${GREEN}✓ No active alarms${NC}"
fi

echo -e "\n${BLUE}========================================${NC}"
echo -e "${GREEN}Health check completed for $BRANCH_NAME${NC}"
echo -e "${BLUE}========================================${NC}"