output "cluster_name" {
  value = aws_eks_cluster.eks.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.eks.endpoint
}

output "cluster_ca_certificate" {
  value = aws_eks_cluster.eks.certificate_authority[0].data
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.eks_oidc.arn
}

output "oidc_issuer" {
  value = aws_eks_cluster.eks.identity[0].oidc[0].issuer
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "devops_user_credentials" {
  description = "Access keys and login URLs for DevOps users"
  value = {
    for user in var.devops_user_names :
    user => {
      access_key_id     = aws_iam_access_key.devops_keys[user].id
      secret_access_key = aws_iam_access_key.devops_keys[user].secret
      console_login_url = "https://console.aws.amazon.com/console/home?region=us-east-1"
    }
  }
  sensitive = true
}
