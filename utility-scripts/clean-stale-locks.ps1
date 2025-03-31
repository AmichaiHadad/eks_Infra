# PowerShell script to clean up stale locks in the DynamoDB table used for state locking
# It will find locks older than the specified age and remove them

# Configuration
$DYNAMO_TABLE = "terraform-locks"
$REGION = "us-east-1"
$MAX_AGE_HOURS = 3 # Consider locks older than this many hours as stale
$STATE_BUCKET_BASE = "eks-terraform-state" # Base name without account ID

# Get AWS account ID
$ACCOUNT_ID = (aws sts get-caller-identity --query Account --output text)
$STATE_BUCKET = "${STATE_BUCKET_BASE}-${ACCOUNT_ID}"

Write-Host "Looking for stale locks in DynamoDB table ${DYNAMO_TABLE} older than ${MAX_AGE_HOURS} hours..."

# Get current time in seconds since epoch
$CURRENT_TIME = [int](Get-Date -UFormat %s)
# Convert hours to seconds
$MAX_AGE_SECONDS = $MAX_AGE_HOURS * 3600

# Scan the DynamoDB table for all locks
$LOCKS_JSON = aws dynamodb scan --table-name $DYNAMO_TABLE --region $REGION --query "Items[*]" --output json
$LOCKS = $LOCKS_JSON | ConvertFrom-Json

# Process each lock
foreach ($lock in $LOCKS) {
    $LOCK_ID = $lock.LockID.S
    
    # Extract information from the lock
    if ($lock.PSObject.Properties.Name -contains "Info") {
        $LOCK_INFO = $lock.Info.S
        
        # Try to parse the created time
        if ($LOCK_INFO -match '"Created":"([^"]*)"') {
            $CREATED_TIME = $matches[1]
            
            try {
                # Convert to DateTime then to seconds since epoch
                $CREATED_DATE = [DateTime]::Parse($CREATED_TIME)
                $CREATED_SECONDS = [int][double]::Parse((Get-Date $CREATED_DATE -UFormat %s))
                
                # Calculate age in seconds
                $AGE_SECONDS = $CURRENT_TIME - $CREATED_SECONDS
                
                if ($AGE_SECONDS -gt $MAX_AGE_SECONDS) {
                    Write-Host "Found stale lock: $LOCK_ID (Age: $([math]::Floor($AGE_SECONDS / 3600)) hours)"
                    Write-Host "  Created: $CREATED_TIME"
                    Write-Host "  Info: $LOCK_INFO"
                    
                    $confirmation = Read-Host "Do you want to delete this lock? (y/n)"
                    if ($confirmation -eq 'y') {
                        Write-Host "Deleting lock..."
                        aws dynamodb delete-item --table-name $DYNAMO_TABLE --key "{{""LockID"": {{""S"": ""$LOCK_ID""}}}}" --region $REGION
                        Write-Host "Lock deleted."
                    }
                    else {
                        Write-Host "Skipping deletion."
                    }
                }
                else {
                    $hours = [math]::Floor($AGE_SECONDS / 3600)
                    $minutes = [math]::Floor(($AGE_SECONDS % 3600) / 60)
                    Write-Host "Lock is not stale: $LOCK_ID (Age: ${hours} hours ${minutes} minutes)"
                }
            }
            catch {
                Write-Host "Could not parse creation time for lock: $LOCK_ID"
                Write-Host "  Error: $_"
            }
        }
        else {
            Write-Host "Lock has no creation time: $LOCK_ID"
            Write-Host "  Info: $LOCK_INFO"
            
            $confirmation = Read-Host "Do you want to delete this lock anyway? (y/n)"
            if ($confirmation -eq 'y') {
                Write-Host "Deleting lock..."
                aws dynamodb delete-item --table-name $DYNAMO_TABLE --key "{{""LockID"": {{""S"": ""$LOCK_ID""}}}}" --region $REGION
                Write-Host "Lock deleted."
            }
            else {
                Write-Host "Skipping deletion."
            }
        }
    }
    else {
        Write-Host "Lock has no Info field: $LOCK_ID - Cannot determine age"
        Write-Host "  Raw data: $($lock | ConvertTo-Json -Compress)"
        
        $confirmation = Read-Host "Do you want to delete this lock anyway? (y/n)"
        if ($confirmation -eq 'y') {
            Write-Host "Deleting lock..."
            aws dynamodb delete-item --table-name $DYNAMO_TABLE --key "{{""LockID"": {{""S"": ""$LOCK_ID""}}}}" --region $REGION
            Write-Host "Lock deleted."
        }
        else {
            Write-Host "Skipping deletion."
        }
    }
}

Write-Host "Finished processing locks." 