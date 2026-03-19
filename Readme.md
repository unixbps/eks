# EKS Cluster with ArgoCD

## Structure

```
eks/
├── infra/       # Layer 1 - VPC, EKS cluster, node group, IAM users
├── addons/      # Layer 2 - ALB controller, aws-auth configmap
└── platform/    # Layer 3 - ArgoCD
```

## Prerequisites
- AWS CLI configured with valid credentials
- Terraform >= 1.9
- kubectl installed

## Deploy

Each layer must be deployed in order as each depends on the previous layer's state.

```bash
# Layer 1 - Infra
cd infra
terraform init
terraform apply

# Layer 2 - Addons
cd ../addons
terraform init
terraform apply

# Layer 3 - Platform
cd ../platform
terraform init
terraform apply
```

## Post Deployment - Access ArgoCD

```bash
# 1. Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name eks-cluster

# 2. Get ALB DNS (wait until ADDRESS column is populated)
kubectl get ingress -n argocd argocd-server-ingress

# 3. Get ArgoCD admin password
kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# 4. Open in browser
# http://<ALB-DNS-from-step-2>
# Username: admin
# Password: <from step 3>
```

## Troubleshooting

### Helm release stuck ("cannot re-use a name that is still in use")
```bash
# ALB controller
kubectl delete secret -n kube-system -l name=aws-load-balancer-controller,owner=helm --ignore-not-found

# ArgoCD
kubectl delete secret -n argocd -l name=argocd,owner=helm --ignore-not-found

terraform apply
```

### ALB controller logs
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50
```

### ArgoCD pod logs
```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=50
```

### Ingress not getting an ADDRESS
```bash
kubectl describe ingress argocd-server-ingress -n argocd
```

## Destroy

Destroy in reverse order to avoid dependency errors.

```bash
cd platform && terraform destroy
cd ../addons && terraform destroy
cd ../infra && terraform destroy
```
