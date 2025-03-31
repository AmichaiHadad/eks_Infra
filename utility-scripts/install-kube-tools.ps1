# PowerShell script to install kubectl and other necessary tools for working with EKS

# Install kubectl
Write-Host "Installing kubectl..."
$kubectlVersion = (Invoke-WebRequest -Uri "https://dl.k8s.io/release/stable.txt" -UseBasicParsing).Content.Trim()
$kubectlUrl = "https://dl.k8s.io/release/$kubectlVersion/bin/windows/amd64/kubectl.exe"
Invoke-WebRequest -Uri $kubectlUrl -OutFile kubectl.exe
# Move to a directory in PATH
$installPath = "$env:USERPROFILE\.local\bin"
if (!(Test-Path $installPath)) {
    New-Item -ItemType Directory -Path $installPath -Force | Out-Null
}
Move-Item -Force kubectl.exe $installPath
# Add to PATH if not already in it
if ($env:PATH -notlike "*$installPath*") {
    [Environment]::SetEnvironmentVariable("PATH", $env:PATH + ";$installPath", "User")
    $env:PATH += ";$installPath"
    Write-Host "Added $installPath to PATH"
}

# Install AWS CLI if not present
if (!(Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-Host "Installing AWS CLI..."
    $awsCliUrl = "https://awscli.amazonaws.com/AWSCLIV2.msi"
    $awsCliInstaller = "$env:TEMP\AWSCLIV2.msi"
    Invoke-WebRequest -Uri $awsCliUrl -OutFile $awsCliInstaller
    Start-Process msiexec.exe -Wait -ArgumentList "/i $awsCliInstaller /quiet"
    Remove-Item $awsCliInstaller
}

# Install eksctl if not present
if (!(Get-Command eksctl -ErrorAction SilentlyContinue)) {
    Write-Host "Installing eksctl..."
    $tempZip = "$env:TEMP\eksctl.zip"
    Invoke-WebRequest -Uri "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_Windows_amd64.zip" -OutFile $tempZip
    Expand-Archive -Path $tempZip -DestinationPath $installPath -Force
    Remove-Item $tempZip
}

# Configure kubectl to use the EKS cluster
Write-Host "`nTo configure kubectl for your EKS cluster, run:"
Write-Host "aws eks update-kubeconfig --region us-east-1 --name eks-cluster" 