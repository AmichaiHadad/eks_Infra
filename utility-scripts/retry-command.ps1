# PowerShell retry script for terragrunt commands that may encounter state lock timeouts
# Usage: .\retry-command.ps1 [command] [args...]

$MAX_RETRIES = 5
$RETRY_DELAY = 10

$retry_count = 0
$exit_code = 0

while ($retry_count -lt $MAX_RETRIES) {
    # Execute the command
    & $args[0] $args[1..($args.Length - 1)]
    $exit_code = $LASTEXITCODE
    
    # If command succeeded, exit
    if ($exit_code -eq 0) {
        exit 0
    }
    
    # Check if the error is a state lock error
    $output = (terraform output) 2>&1
    if ($output -match "Error acquiring the state lock" -or 
        $output -match "Failed to acquire the state lock" -or 
        $output -match "conflict operation in progress") {
        
        $retry_count++
        if ($retry_count -lt $MAX_RETRIES) {
            Write-Host "Encountered state lock error. Retrying in ${RETRY_DELAY} seconds... (Attempt ${retry_count}/${MAX_RETRIES})"
            Start-Sleep -Seconds $RETRY_DELAY
            continue
        }
        else {
            Write-Host "Max retries reached. Failed to acquire state lock."
        }
    }
    else {
        # If it's not a state lock error, don't retry
        Write-Host "Command failed with non-lock error. Not retrying."
        break
    }
}

# Exit with the last exit code
exit $exit_code 