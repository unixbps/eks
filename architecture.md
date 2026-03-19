# EKS Architecture - Components & Purpose

## AWS Components

### Networking
| Resource | Purpose |
|---|---|
| `aws_vpc` | Isolated network (`10.0.0.0/16`) for all cluster resources |
| `aws_subnet` public x2 | Public-facing subnets in 2 AZs — ALB lives here |
| `aws_subnet` private x2 | Private subnets in same 2 AZs — EKS worker nodes live here |
| `aws_internet_gateway` | Allows public subnets to reach the internet |
| `aws_nat_gateway` | Allows private subnet nodes to reach internet (pull images, AWS APIs) without being publicly exposed |
| `aws_eip` | Static IP attached to the NAT gateway |
| `aws_route_table` public | Routes public subnet traffic → internet gateway |
| `aws_route_table` private | Routes private subnet traffic → NAT gateway |
| `aws_security_group` | Allows all traffic between nodes within the cluster |

### EKS
| Resource | Purpose |
|---|---|
| `aws_eks_cluster` | The Kubernetes control plane — managed by AWS (API server, etcd, scheduler) |
| `aws_eks_node_group` | 3x `t3.medium` EC2 worker nodes in private subnets — runs your pods |
| `aws_iam_openid_connect_provider` | OIDC provider — lets Kubernetes service accounts assume AWS IAM roles (IRSA) |

### IAM — Cluster
| Resource | Purpose |
|---|---|
| `aws_iam_role` eks_cluster_role | Role assumed by EKS control plane to manage AWS resources |
| `aws_iam_role` eks_node_role | Role assumed by EC2 worker nodes |
| `AmazonEKSClusterPolicy` | Allows EKS to manage the cluster |
| `AmazonEKSWorkerNodePolicy` | Allows nodes to join the cluster |
| `AmazonEKS_CNI_Policy` | Allows VPC CNI plugin to assign pod IPs from subnet |
| `AmazonEC2ContainerRegistryReadOnly` | Allows nodes to pull images from ECR |

### IAM — ALB Controller
| Resource | Purpose |
|---|---|
| `aws_iam_role` alb_controller | Role assumed by the ALB controller pod via IRSA |
| `aws_iam_policy` alb_controller | Full set of EC2/ELB permissions needed to create and manage ALBs |

### IAM — DevOps Users
| Resource | Purpose |
|---|---|
| `aws_iam_user` x10 | 10 DevOps team members (`devops-user-01` to `10`) |
| `aws_iam_user_login_profile` | Console login with forced password reset on first login |
| `aws_iam_access_key` | Programmatic access keys (AWS CLI) |
| `ReadOnlyAccess` policy | Read-only AWS console access for all devops users |

---

## Kubernetes Components

### Cluster Access
| Resource | Purpose |
|---|---|
| `kubernetes_config_map` aws-auth | Maps AWS IAM users to Kubernetes RBAC — gives devops users `system:masters` (admin) access to the cluster |

### ALB Controller
| Resource | Purpose |
|---|---|
| `kubernetes_service_account` alb-controller | K8s identity for the ALB controller pod, annotated with the IAM role ARN for IRSA |
| `helm_release` aws-load-balancer-controller | Deploys the ALB controller — watches Ingress resources and creates/manages AWS ALBs automatically |

### ArgoCD
| Resource | Purpose |
|---|---|
| `helm_release` argocd | Deploys ArgoCD in the `argocd` namespace — GitOps controller that syncs K8s resources from Git repos |
| `kubectl_manifest` argocd_ingress | Creates an Ingress resource that tells the ALB controller to create an internet-facing ALB pointing to the ArgoCD server |

---

## How They Connect

```
Internet → ALB (created by ALB controller from Ingress)
         → ArgoCD pod (in private subnet)

EKS nodes (private subnet) → NAT Gateway → Internet (for image pulls, AWS API calls)

ArgoCD pod → IRSA not needed (no AWS API calls)
ALB controller pod → IRSA → IAM role → AWS ELB/EC2 APIs
DevOps users → aws-auth configmap → Kubernetes RBAC → cluster access
```

---

## Terraform Layer Structure

```
eks/
├── infra/       # Layer 1 - VPC, EKS cluster, node group, IAM users
├── addons/      # Layer 2 - ALB controller, aws-auth configmap
└── platform/    # Layer 3 - ArgoCD
```

- `addons` and `platform` read outputs from `infra` via `terraform_remote_state`
- Each layer has its own state file — changes in one layer don't affect others
- Deploy in order: `infra` → `addons` → `platform`
- Destroy in reverse: `platform` → `addons` → `infra`
