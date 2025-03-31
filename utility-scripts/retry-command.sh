#!/bin/bash

# Retry script for terragrunt commands that may encounter state lock timeouts
# Usage: ./retry-command.sh [command] [args...]

MAX_RETRIES=5
RETRY_DELAY=10

retry_count=0
exit_code=0

while [ $retry_count -lt $MAX_RETRIES ]; do
  # Execute the command
  "$@"
  exit_code=$?
  
  # If command succeeded, exit
  if [ $exit_code -eq 0 ]; then
    exit 0
  fi
  
  # Check if the error is a state lock error
  output=$(terraform output 2>&1)
  if echo "$output" | grep -q "Error acquiring the state lock" || \
     echo "$output" | grep -q "Failed to acquire the state lock" || \
     echo "$output" | grep -q "conflict operation in progress"; then
    
    retry_count=$((retry_count + 1))
    if [ $retry_count -lt $MAX_RETRIES ]; then
      echo "Encountered state lock error. Retrying in ${RETRY_DELAY} seconds... (Attempt ${retry_count}/${MAX_RETRIES})"
      sleep $RETRY_DELAY
      continue
    else
      echo "Max retries reached. Failed to acquire state lock."
    fi
  else
    # If it's not a state lock error, don't retry
    echo "Command failed with non-lock error. Not retrying."
    break
  fi
done

# Exit with the last exit code
exit $exit_code 