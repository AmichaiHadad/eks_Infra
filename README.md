# EKS Cluster with Terraform and Terragrunt

This project sets up a production-grade Amazon EKS (Elastic Kubernetes Service) cluster using Terraform modules orchestrated with Terragrunt. The infrastructure implements all requirements specified in the exercise plan.

## Important Note About This Project

This project **only sets up the Kubernetes infrastructure** (EKS cluster and node groups). It does not deploy any actual applications like Prometheus, Grafana, Argo CD, or Elasticsearch. The node groups are prepared with appropriate taints and labels to host these types of workloads, but you would need to deploy the applications separately after the infrastructure is ready.

## Exercise Requirements Implementation

### 1. Cluster Infrastructure Setup

#### VPC Creation ✅
- **Implemented in:** `modules/vpc` and `terragrunt/stacks/vpc`
- 3 private and 3 public subnets across multiple availability zones
- Internet Gateway for public subnet internet access
- NAT Gateways (one per AZ) for private subnet internet access
- Appropriate route tables and security groups
- Enhanced with VPC endpoints for secure AWS service access

#### EKS Cluster ✅
- **Implemented in:** `modules/eks` and `terragrunt/stacks/eks-cluster`
- Configurable cluster name and version
- IAM roles and policies for EKS control plane
- Private API endpoint with optional public access
- Control plane managed by AWS

#### Node Groups ✅
- **Implemented in:** `modules/node-group` and `terragrunt/stacks/node-groups/*`
- All node groups have auto-scaling enabled
- Configurable instance types, capacity settings, and IAM roles
- Four specialized node groups:
  1. **Monitoring Node Group:** Prepared for monitoring tools like Prometheus/Grafana
  2. **Management Node Group:** Prepared for management tools like Argo CD
  3. **Services Node Group:** Prepared for application services
  4. **Data Node Group:** Prepared for data services like Elasticsearch

#### Networking and Security ✅
- Private endpoints for the EKS cluster
- Restricted API access using security groups
- Enhanced with proper security group rules for node communication

#### IAM Roles and Policies ✅
- IAM roles for EKS control plane with proper permissions
- IAM roles for each node group with appropriate policies

### 2. Tools and Implementation

#### Terraform Modules ✅
- Uses official AWS modules and custom reusable modules
- Modular structure with proper separation of concerns

#### Terragrunt Configuration ✅
- Maintains stack dependencies in terragrunt.hcl files
- DRY principles with shared configurations

#### Repository Structure ✅
- Separate directories for VPC, EKS cluster, and node groups
- Modular and reusable Terraform code

## Project Structure

```
.
├── modules/                            # Reusable Terraform modules
│   ├── vpc/                            # VPC module
│   ├── eks/                            # EKS cluster module
│   ├── node-group/                     # Node group module
│   └── eks-addons/                     # EKS addons module
│
└── terragrunt/
    ├── terragrunt.hcl                  # Root Terragrunt configuration
    └── stacks/
        ├── vpc/                        # VPC configuration
        ├── eks-cluster/                # EKS cluster configuration (without addons)
        ├── node-groups/                # Node group configurations
        │   ├── monitoring/             # For monitoring tools (Prometheus/Grafana)
        │   ├── management/             # For management tools (Argo CD)
        │   ├── services/               # For application services
        │   └── data/                   # For data services (Elasticsearch)
        └── eks-addons/                 # Enable EKS addons after node groups exist
```

## Prerequisites

- Terraform (v1.0.0+)
- Terragrunt (v0.35.0+)
- AWS CLI configured with appropriate permissions
- An S3 bucket for remote state storage (referenced in `terragrunt.hcl` as "eks-terraform-state-${account_id}")
- A DynamoDB table named "terraform-locks" for state locking

## Infrastructure Components

### VPC
- 3 private and 3 public subnets across multiple availability zones
- NAT Gateways (one per AZ) for private subnet internet access
- Internet Gateway for public subnet internet access
- Appropriate route tables and security groups

### EKS Cluster
- Kubernetes control plane managed by AWS
- Private API endpoint with optional public access
- Proper IAM roles and security configurations

### Node Groups
1. **Monitoring Node Group**
   - Purpose: Prepared for monitoring tools like Prometheus and Grafana
   - Instance type: t3.medium
   - Tainted to only run monitoring workloads

2. **Management Node Group**
   - Purpose: Prepared for management tools like Argo CD
   - Instance type: t3.medium
   - Tainted to only run management workloads

3. **Services Node Group**
   - Purpose: Prepared for application services and workloads
   - Instance type: t3.medium
   - Not tainted, allowing general workloads

4. **Data Node Group**
   - Purpose: Prepared for data services like Elasticsearch
   - Instance type: r5.2xlarge (memory optimized)
   - Tainted to only run data workloads

## Deployment Instructions

### 1. Initialize the S3 bucket and DynamoDB table

Before starting, ensure your S3 bucket and DynamoDB table exist:

```bash
# Create the S3 bucket for state storage (replace with your account ID)
aws s3api create-bucket --bucket eks-terraform-state-YOUR_ACCOUNT_ID --region us-east-1
aws s3api put-bucket-versioning --bucket eks-terraform-state-YOUR_ACCOUNT_ID --versioning-configuration Status=Enabled

# Create the DynamoDB table for state locking
aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

# Wait for the DynamoDB table to become active
aws dynamodb wait table-exists --table-name terraform-locks
```

Update the `terragrunt/terragrunt.hcl` file with your bucket name if needed.

### 2. Deploy the infrastructure

Deploy the stacks in the following order:

```bash
# 1. Deploy the VPC
cd terragrunt/stacks/vpc
terragrunt apply

# 2. Deploy the EKS cluster (without addons)
cd ../eks-cluster
terragrunt apply

# 3. Deploy the monitoring node group
cd ../node-groups/monitoring
terragrunt apply

# 4. Deploy the management node group
cd ../management
terragrunt apply

# 5. Now enable the EKS addons (includes CNI)
cd ../../eks-addons
terragrunt apply

# 6. Deploy the services node group
cd ../node-groups/services
terragrunt apply

# 7. Deploy the data node group
cd ../data
terragrunt apply
```

This deployment order is critical and must be followed exactly as shown to ensure proper dependency handling.

### Cross-Platform Support

This project provides scripts for both Windows PowerShell and Linux/macOS environments in the `utility-scripts` directory:

- Installation tools: `utility-scripts/install-kube-tools.sh` and `utility-scripts/install-kube-tools.ps1`
- Cleanup scripts: `utility-scripts/cleanup-resources.sh` and `utility-scripts/cleanup-resources.ps1`
- Helper scripts: `utility-scripts/retry-command.sh` and `utility-scripts/retry-command.ps1`

Always use the appropriate script for your operating system.

### Wait Times
- **VPC resources**: ~5 minutes
- **EKS cluster**: ~10-15 minutes
- **Node groups**: ~10-15 minutes each
- **EKS addons**: ~5-10 minutes

If you see a resource creation taking much longer than these estimates, check the troubleshooting section below.

## Accessing the Cluster

After deployment, configure your kubectl:

```bash
aws eks update-kubeconfig --region us-east-1 --name eks-cluster
```

Verify the cluster is working correctly:
```bash
kubectl get nodes
kubectl get pods -A
```

## Next Steps After Deployment

After the infrastructure is deployed, you can install applications on the appropriate node groups:

1. **On Monitoring nodes:** Deploy Prometheus and Grafana using Helm charts
2. **On Management nodes:** Deploy Argo CD using Helm charts or manifests
3. **On Services nodes:** Deploy your application workloads
4. **On Data nodes:** Deploy Elasticsearch or other data services

These applications are not included in this project and would need to be deployed separately.

## Customization

- Update instance types and sizes in the respective `terragrunt.hcl` files
- Adjust auto-scaling parameters based on your workload needs
- Modify security groups and access control as needed

## Cleanup

To destroy all resources in the exact reverse order of creation:

```bash
# 1. First destroy the data node group
cd terragrunt/stacks/node-groups/data
terragrunt destroy

# 2. Destroy the services node group
cd ../services
terragrunt destroy

# 3. Destroy the EKS addons
cd ../../eks-addons
terragrunt destroy

# 4. Destroy the management node group
cd ../node-groups/management
terragrunt destroy

# 5. Destroy the monitoring node group
cd ../monitoring
terragrunt destroy

# 6. Destroy the EKS cluster
cd ../../eks-cluster
terragrunt destroy

# 7. Finally destroy the VPC
cd ../vpc
terragrunt destroy
```

### Cleaning Up Failed Deployments

If a deployment fails and you need to clean up resources before trying again, you can use the provided cleanup scripts:

1. For Windows PowerShell:
```bash
cd utility-scripts
powershell -ExecutionPolicy Bypass -File cleanup-resources.ps1
```

2. For Unix/Linux:
```bash
cd utility-scripts
chmod +x cleanup-resources.sh
./cleanup-resources.sh
```

These scripts will automatically find and clean up:
- Auto scaling groups
- EKS node groups
- IAM roles and instance profiles
- Security groups
- Launch templates

Alternatively, you can manually clean up resources using these commands:

1. Check for orphaned IAM roles:
```bash
aws iam list-roles | grep eks
```

2. Delete any roles that were created but not properly managed by Terraform:
```bash
aws iam detach-role-policy --role-name ROLE_NAME --policy-arn POLICY_ARN
# Repeat for all attached policies
aws iam delete-role --role-name ROLE_NAME
```

3. Check for orphaned security groups:
```bash
aws ec2 describe-security-groups | grep node-sg
```

4. Delete any security groups that were created but not properly managed:
```bash
aws ec2 delete-security-group --group-id SG_ID
```

5. Check and delete any launch templates:
```bash
aws ec2 describe-launch-templates | grep eks
aws ec2 delete-launch-template --launch-template-id LT_ID
```

## Security Considerations

- The EKS API server is publicly accessible but restricted by CIDR blocks
- Worker nodes are placed in private subnets
- Proper IAM roles with least privilege are used
- IMDSv2 is enabled on EC2 instances for improved security

## Troubleshooting

### Node Group Creation Hanging
If a node group creation is hanging for more than 15 minutes:
1. Check the AWS console for EC2 Auto Scaling activity
2. Verify the subnets have proper routes to the internet via NAT gateways
3. Check that the security groups allow necessary traffic
4. Ensure the IAM roles have proper permissions

### CNI Initialization Issues
If nodes are reporting "container runtime network not ready: NetworkReady=false reason:NetworkPluginNotReady message:cni plugin not initialized":

1. Ensure the proper deployment order is followed (VPC → EKS Cluster → Monitoring/Management → EKS Addons → Services/Data)
2. SSH to the problematic node using SSM and run the included diagnostic script:
   ```bash
   sudo /home/ec2-user/debug-eks.sh
   ```
3. To fix CNI issues manually, run the included repair script:
   ```bash
   sudo /home/ec2-user/fix-cni.sh
   ```
4. If the issue persists, verify that the VPC CNI addon is properly installed:
   ```bash
   aws eks describe-addon --cluster-name eks-cluster --addon-name vpc-cni
   ```
5. Use the included EKS addon status checking tools to verify all addons are properly deployed:

   For Windows:
   ```powershell
   cd utility-scripts
   .\check-eks-addons.ps1
   ```

   For Linux/macOS:
   ```bash
   cd utility-scripts
   ./check-eks-addons.sh
   ```

The enhanced node bootstrap scripts should automatically handle most CNI issues, but these tools are provided for manual intervention if needed.

### State Lock Issues
If you encounter state lock issues when running Terragrunt:

1. First, try waiting a few minutes and then retrying the operation
2. If the lock persists, use the included lock cleaning tools:

   For Windows:
   ```powershell
   cd utility-scripts
   .\clean-stale-locks.ps1
   ```

   For Linux/macOS:
   ```bash
   cd utility-scripts
   ./clean-stale-locks.sh
   ```

3. For a specific known lock, use terragrunt force-unlock:
   ```bash
   terragrunt force-unlock <LOCK_ID>
   ```

The enhanced terragrunt.hcl configuration includes several improvements to make state locks more reliable:
- Longer retry timeouts
- More comprehensive retry patterns
- Automatic lock status checking

### Resource Already Exists Errors
If you encounter "resource already exists" errors:
1. First try to import the existing resource into your Terraform state
   ```bash
   terragrunt import <RESOURCE_TYPE>.<RESOURCE_NAME> <RESOURCE_ID>
   ```
2. If import fails, follow the "Cleaning Up Failed Deployments" section to remove the orphaned resources manually

### CoreDNS Addon Issues
If the CoreDNS addon fails to deploy:
1. Make sure at least one node group is up and running before enabling addons
2. Check the node group status with `kubectl get nodes`
3. Verify node taints aren't preventing CoreDNS pods from scheduling

### Persistent Volume Issues
If applications can't create persistent volumes:
1. Ensure the EBS CSI driver is installed
2. Check IAM permissions for the node groups
3. Verify that the storage class is correctly configured

### Node Communication Issues
If nodes can't communicate with each other or the control plane:
1. Check the security group rules
2. Verify network ACLs aren't blocking traffic
3. Check subnet routing tables

### AWS CLI Access Issues
If AWS CLI can't interact with the cluster:
1. Update your kubeconfig using the command in the "Accessing the Cluster" section
2. Verify your AWS credentials have proper permissions
3. Check if your IAM role has permissions to access EKS 