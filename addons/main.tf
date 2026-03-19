terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0.0"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.0.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "terraform_remote_state" "infra" {
  backend = "local"
  config = {
    path = "../infra/terraform.tfstate"
  }
}

locals {
  cluster_name     = data.terraform_remote_state.infra.outputs.cluster_name
  cluster_endpoint = data.terraform_remote_state.infra.outputs.cluster_endpoint
  cluster_ca       = data.terraform_remote_state.infra.outputs.cluster_ca_certificate
  oidc_provider_arn = data.terraform_remote_state.infra.outputs.oidc_provider_arn
  oidc_issuer      = data.terraform_remote_state.infra.outputs.oidc_issuer
  vpc_id           = data.terraform_remote_state.infra.outputs.vpc_id
}

provider "kubernetes" {
  host                   = local.cluster_endpoint
  cluster_ca_certificate = base64decode(local.cluster_ca)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.cluster_name]
  }
}

provider "helm" {
  kubernetes = {
    host                   = local.cluster_endpoint
    cluster_ca_certificate = base64decode(local.cluster_ca)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name]
    }
  }
}

# aws-auth configmap
variable "aws_account_id" {
  type    = string
  default = "608283508317"
}

variable "devops_user_names" {
  default = [
    "devops-user-01", "devops-user-02", "devops-user-03", "devops-user-04", "devops-user-05",
    "devops-user-06", "devops-user-07", "devops-user-08", "devops-user-09", "devops-user-10"
  ]
}


# ALB Controller IAM
resource "aws_iam_role" "alb_controller" {
  name = "alb-controller-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = local.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(local.oidc_issuer, "https://", "")}:sub" = "system:serviceaccount:kube-system:alb-controller"
        }
      }
    }]
  })
}

data "http" "alb_controller_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json"
}

resource "aws_iam_policy" "alb_controller" {
  name   = "AWSLoadBalancerControllerIAMPolicy"
  policy = data.http.alb_controller_policy.response_body
}

resource "aws_iam_role_policy_attachment" "alb_controller_attach" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

resource "kubernetes_service_account" "alb_controller" {
  metadata {
    name      = "alb-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.alb_controller.arn
    }
  }
}

resource "helm_release" "alb_controller" {
  depends_on      = [kubernetes_service_account.alb_controller]
  name            = "aws-load-balancer-controller"
  repository      = "https://aws.github.io/eks-charts"
  chart           = "aws-load-balancer-controller"
  namespace       = "kube-system"
  wait            = true
  timeout         = 300
  cleanup_on_fail = true

  set = [
    { name = "clusterName", value = local.cluster_name },
    { name = "serviceAccount.create", value = "false" },
    { name = "serviceAccount.name", value = kubernetes_service_account.alb_controller.metadata[0].name },
    { name = "vpcId", value = local.vpc_id },
    { name = "region", value = "us-east-1" }
  ]
}
