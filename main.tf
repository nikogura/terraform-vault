# Main Entrypoint for the module.
locals {
  vault_user_data = templatefile(
    var.custom_userdata_path != null ? var.custom_userdata_path : "${path.module}/install_vault.sh.tpl",
    {
      region                = var.aws_region
      name                  = var.resource_name_prefix
      vault_version         = var.vault_version
      kms_key_arn           = var.kms_key_arn != null ? var.kms_key_arn : aws_kms_key.vault[0].arn
      secrets_manager_arn   = var.secrets_manager_arn != null? var.secrets_manager_arn : aws_secretsmanager_secret.tls.arn
      leader_tls_servername = var.vault_lb_hostname != null? var.vault_lb_hostname : aws_lb.vault_lb.dns_name
    }
  )
  vpc_id =  var.vpc_id
}

# Data source that looks for all the subnets in your VPC and returns the ones containing tags that suggest that they're private.
# Obviously, this means you need to tag your private and public subnets distinctly.
data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }

  tags   = var.private_subnet_tags
}