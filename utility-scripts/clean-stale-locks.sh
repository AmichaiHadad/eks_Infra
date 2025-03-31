#!/bin/bash
# This script cleans up stale locks in the DynamoDB table used for state locking
# It will find locks older than the specified age and remove them

set -e

# Configuration
DYNAMO_TABLE="terraform-locks"
REGION="us-east-1"
MAX_AGE_HOURS=3 # Consider locks older than this many hours as stale
STATE_BUCKET="eks-terraform-state" # Base name without account ID

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
STATE_BUCKET="${STATE_BUCKET}-${ACCOUNT_ID}"

echo "Looking for stale locks in DynamoDB table ${DYNAMO_TABLE} older than ${MAX_AGE_HOURS} hours..."

# Get current time in seconds since epoch
CURRENT_TIME=$(date +%s)
# Convert hours to seconds
MAX_AGE_SECONDS=$((MAX_AGE_HOURS * 3600))

# Scan the DynamoDB table for all locks
LOCKS=$(aws dynamodb scan --table-name ${DYNAMO_TABLE} --region ${REGION} --query "Items[*]" --output json)

# Process each lock
echo "$LOCKS" | jq -c '.[]' | while read -r lock; do
  LOCK_ID=$(echo "$lock" | jq -r '.LockID.S')
  
  # Extract information from the lock
  if echo "$lock" | jq -e '.Info.S' > /dev/null 2>&1; then
    LOCK_INFO=$(echo "$lock" | jq -r '.Info.S')
    CREATED_TIME=$(echo "$LOCK_INFO" | grep -o '"Created":"[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$CREATED_TIME" ]; then
      # Convert to seconds since epoch (ISO 8601 format)
      CREATED_SECONDS=$(date -d "${CREATED_TIME}" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S%z" "${CREATED_TIME}" +%s 2>/dev/null)
      
      if [ -n "$CREATED_SECONDS" ]; then
        # Calculate age in seconds
        AGE_SECONDS=$((CURRENT_TIME - CREATED_SECONDS))
        
        if [ $AGE_SECONDS -gt $MAX_AGE_SECONDS ]; then
          echo "Found stale lock: $LOCK_ID (Age: $(($AGE_SECONDS / 3600)) hours)"
          echo "  Created: $CREATED_TIME"
          echo "  Info: $LOCK_INFO"
          
          read -p "Do you want to delete this lock? (y/n): " -n 1 -r
          echo
          if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Deleting lock..."
            aws dynamodb delete-item --table-name ${DYNAMO_TABLE} --key "{\"LockID\": {\"S\": \"$LOCK_ID\"}}" --region ${REGION}
            echo "Lock deleted."
          else
            echo "Skipping deletion."
          fi
        else
          echo "Lock is not stale: $LOCK_ID (Age: $(($AGE_SECONDS / 3600)) hours $(($AGE_SECONDS % 3600 / 60)) minutes)"
        fi
      else
        echo "Could not parse creation time for lock: $LOCK_ID"
      fi
    else
      echo "Lock has no Info field: $LOCK_ID - Cannot determine age"
      echo "  Raw data: $lock"
      
      read -p "Do you want to delete this lock anyway? (y/n): " -n 1 -r
      echo
      if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deleting lock..."
        aws dynamodb delete-item --table-name ${DYNAMO_TABLE} --key "{\"LockID\": {\"S\": \"$LOCK_ID\"}}" --region ${REGION}
        echo "Lock deleted."
      else
        echo "Skipping deletion."
      fi
    fi
  else
    echo "Lock has no Info field: $LOCK_ID - Cannot determine age"
    
    read -p "Do you want to delete this lock anyway? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      echo "Deleting lock..."
      aws dynamodb delete-item --table-name ${DYNAMO_TABLE} --key "{\"LockID\": {\"S\": \"$LOCK_ID\"}}" --region ${REGION}
      echo "Lock deleted."
    else
      echo "Skipping deletion."
    fi
  fi
done

echo "Finished processing locks." 