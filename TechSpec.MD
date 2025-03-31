# EKS Infrastructure Technical Specification

## 1. Infrastructure Overview

This document describes the Amazon EKS (Elastic Kubernetes Service) infrastructure created using Terraform and Terragrunt. The infrastructure follows AWS best practices and is designed to host different types of workloads in isolation.

**Key Components:**
- Multi-AZ VPC with public and private subnets
- EKS Cluster (v1.28) with private API endpoint
- Four specialized node groups with different taints and labels
- Enhanced networking with VPC endpoints for AWS services
- Comprehensive IAM roles and security groups

## 2. VPC Configuration

| Component | Details |
|-----------|---------|
| **CIDR Block** | 10.0.0.0/16 |
| **Region** | us-east-1 |
| **Availability Zones** | us-east-1a, us-east-1b, us-east-1c |
| **Private Subnets** | 10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24 |
| **Public Subnets** | 10.0.101.0/24, 10.0.102.0/24, 10.0.103.0/24 |
| **NAT Gateways** | One per AZ (3 total) |
| **Internet Gateway** | Yes |

**VPC Endpoints:**
- S3 Gateway Endpoint
- Interface Endpoints: ECR (API & DKR), EC2, CloudWatch Logs, EKS, STS, SSM, SSMMMessages

## 3. EKS Cluster Configuration

| Component | Details |
|-----------|---------|
| **Cluster Name** | eks-cluster |
| **Kubernetes Version** | 1.28 |
| **API Endpoint Access** | Private with optional public access |
| **Subnet Placement** | Private subnets |
| **Control Plane Logging** | Enabled for API, audit, authenticator, controllerManager, scheduler |

**Addons:**
- Amazon VPC CNI (v1.19.0) - Networking
- CoreDNS - DNS resolution
- kube-proxy - Network proxy

## 4. Node Groups Configuration

### 4.1. Monitoring Node Group
- **Purpose**: Hosts monitoring tools (Prometheus, Grafana)
- **Instance Type**: t3.medium
- **Capacity Type**: ON_DEMAND
- **Desired/Min/Max Capacity**: 2/2/4
- **Disk Size**: 50 GiB (gp3)
- **Taints**: `dedicated=monitoring:NO_SCHEDULE`
- **Labels**: `role=monitoring`, `tier=management`
- **Max Pods per Node**: 110

### 4.2. Management Node Group
- **Purpose**: Hosts management tools (Argo CD)
- **Instance Type**: t3.medium
- **Capacity Type**: ON_DEMAND
- **Desired/Min/Max Capacity**: 2/1/4
- **Disk Size**: 50 GiB (gp3)
- **Taints**: `dedicated=management:NO_SCHEDULE`
- **Labels**: `role=management`, `tier=management`
- **Max Pods per Node**: 110

### 4.3. Services Node Group
- **Purpose**: Hosts application services and workloads
- **Instance Type**: t3.medium
- **Capacity Type**: ON_DEMAND
- **Desired/Min/Max Capacity**: 2/1/4
- **Disk Size**: 50 GiB (gp3)
- **Taints**: None
- **Labels**: `role=services`, `tier=application`, `cni-initialized=true`
- **Max Pods per Node**: 110

### 4.4. Data Node Group
- **Purpose**: Hosts data services (Elasticsearch, etc.)
- **Instance Type**: r5.2xlarge (memory-optimized)
- **Capacity Type**: ON_DEMAND
- **Desired/Min/Max Capacity**: 2/2/5
- **Disk Size**: 100 GiB (gp3)
- **Taints**: `dedicated=data:NO_SCHEDULE`
- **Labels**: `node-type=data`, `workload=data`
- **Max Pods per Node**: 110

## 5. Networking and Connectivity

### 5.1. Pod Networking
- **CNI**: Amazon VPC CNI
- **Pod CIDR**: Uses VPC CIDR (follows AWS VPC CNI model)
- **Pod Density**: Maximum 110 pods per node
- **CNI Configuration**:
  - WARM_ENI_TARGET: 1
  - WARM_IP_TARGET: 1
  - ENABLE_PREFIX_DELEGATION: false

### 5.2. Service Networking
- **Service CIDR**: 10.100.0.0/16
- **Kubernetes DNS Service IP**: 10.100.0.10
- **Cluster DNS Provider**: CoreDNS

### 5.3. Network Policies
- Network policies can be implemented via standard Kubernetes NetworkPolicy resources
- Amazon VPC CNI supports native enforcement of these policies

## 6. Security Configuration

### 6.1. IAM Roles and Policies
- **EKS Cluster Role**: Permissions for EKS control plane
- **Node Group Roles**: Each node group has its own IAM role with:
  - AmazonEKSWorkerNodePolicy
  - AmazonEKS_CNI_Policy
  - AmazonEC2ContainerRegistryReadOnly
  - AmazonSSMManagedInstanceCore (for troubleshooting)

### 6.2. Security Groups
- **Cluster Security Group**: Controls access to the EKS API server
- **Node Group Security Groups**: One per node group with rules for:
  - Node-to-node communication (all protocols)
  - Control plane to node communication (TCP ports 443, 1025-65535, 10250)
  - DNS communication (UDP port 53)

### 6.3. Node Security
- **IMDSv2 Required**: Yes (HTTP tokens required)
- **EBS Volume Encryption**: Yes
- **SSH Access**: No direct SSH (SSM for emergency access)

## 7. Dependencies and Deployment Order

The components have the following dependencies:

1. VPC (base infrastructure)
2. EKS Cluster (depends on VPC)
3. Monitoring Node Group (depends on EKS Cluster)
4. Management Node Group (depends on EKS Cluster)
5. EKS Addons (depends on Monitoring and Management Node Groups)
6. Services Node Group (depends on EKS Addons)
7. Data Node Group (depends on EKS Addons)

**Deployment best practice**: Follow the exact order above to ensure proper dependency handling.

## 8. Application Deployment Guidelines

### 8.1. Workload Placement

| Workload Type | Target Node Group | Required Tolerations | Example Applications |
|---------------|-------------------|----------------------|----------------------|
| Monitoring Tools | Monitoring | `dedicated=monitoring:NO_SCHEDULE` | Prometheus, Grafana, Alertmanager |
| Management Tools | Management | `dedicated=management:NO_SCHEDULE` | Argo CD, Flux, Cluster Autoscaler |
| Application Services | Services | None | Web applications, APIs, microservices |
| Data Services | Data | `dedicated=data:NO_SCHEDULE` | Elasticsearch, Postgres, MongoDB |

### 8.2. Resource Allocation Guidelines

| Node Group | CPU Request Range | Memory Request Range | Storage Needs |
|------------|-------------------|----------------------|---------------|
| Monitoring | 50m-500m per pod | 128Mi-1Gi per pod | Use 10-20Gi PVs for persistent storage |
| Management | 50m-250m per pod | 128Mi-512Mi per pod | Use 1-5Gi PVs for configuration storage |
| Services | 50m-1000m per pod | 64Mi-2Gi per pod | Application dependent |
| Data | 500m-2000m per pod | 1Gi-16Gi per pod | Use storage classes for persistent data |

### 8.3. Deployment Method Recommendations

1. **Infrastructure as Code**: Use Helm charts or Kubernetes YAML manifests
2. **CI/CD**: Deploy Argo CD on the Management nodes for GitOps workflows
3. **Secrets Management**: Use AWS Secrets Manager or consider external solutions like Vault
4. **Namespace Strategy**:
   - `monitoring`: For monitoring tools
   - `management`: For management tools
   - `default`: For application services
   - `data`: For data services

### 8.4. Network Connectivity

- **Ingress**: Deploy AWS Load Balancer Controller or NGINX Ingress Controller
- **Service Mesh**: Optional - can deploy Istio or AWS App Mesh if needed
- **DNS**: Use External DNS controller for route53 integration

## 9. Troubleshooting Access

Each node has pre-installed troubleshooting utilities:

- `/home/ec2-user/debug-eks.sh`: View logs and diagnostics
- `/home/ec2-user/fix-node-registration.sh`: Fix node registration issues

Use AWS Systems Manager (SSM) to access nodes when needed.

## 10. Cost Optimization

Estimated monthly cost breakdown:
- EKS Cluster: ~$73/month
- EC2 Instances (t3.medium × 6): ~$216/month
- EC2 Instances (r5.2xlarge × 2): ~$833/month
- NAT Gateways (×3): ~$102/month
- EBS Volumes: ~$35/month
- Data Transfer: Varies based on usage

**Total Base Infrastructure: ~$1,259/month** (excluding variable costs like data transfer and load balancers) 