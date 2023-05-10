# IAM resources for Vault

# Vault IAM Profile
resource "aws_iam_instance_profile" "vault" {
  name_prefix = "${var.resource_name_prefix}-vault"
  role        = var.vault_role_name != null ? var.vault_role_name : aws_iam_role.instance_role[0].name
}

resource "aws_iam_role" "instance_role" {
  count              = var.vault_role_name != null ? 0 : 1
  name_prefix        = "${var.resource_name_prefix}-vault"
  assume_role_policy = data.aws_iam_policy_document.instance_role.json
}

# Vault policy document
data "aws_iam_policy_document" "instance_role" {
  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
    ]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# Policy that allows Vault instances to reach out to the AWS API and see what other instances are running.
resource "aws_iam_role_policy" "cloud_auto_join" {
  count  = var.vault_role_name != null ? 0 : 1
  name   = "${var.resource_name_prefix}-vault-auto-join"
  role   = aws_iam_role.instance_role[0].id
  policy = data.aws_iam_policy_document.cloud_auto_join.json
}

data "aws_iam_policy_document" "cloud_auto_join" {
  statement {
    effect = "Allow"

    actions = [
      "ec2:DescribeInstances",
    ]

    resources = ["*"]
  }
}

# Policy that allows Vault to use KMS to encrypt and decrypt the master key when a vault instance starts up.  Without this, the Vault instance has no clue how to read the data in storage.
resource "aws_iam_role_policy" "auto_unseal" {
  count  = var.vault_role_name != null ? 0 : 1
  name   = "${var.resource_name_prefix}-vault-auto-unseal"
  role   = aws_iam_role.instance_role[0].id
  policy = data.aws_iam_policy_document.auto_unseal.json
}

data "aws_iam_policy_document" "auto_unseal" {
  statement {
    effect = "Allow"

    actions = [
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:Decrypt",
    ]

    resources = [
      var.kms_key_arn != null? var.kms_key_arn : aws_kms_key.vault[0].arn,
    ]
  }
}

# Role policy for Session Manager
resource "aws_iam_role_policy" "session_manager" {
  count  = var.vault_role_name != null ? 0 : 1
  name   = "${var.resource_name_prefix}-vault-ssm"
  role   = aws_iam_role.instance_role[0].id
  policy = data.aws_iam_policy_document.session_manager.json
}

# Session Manager Policy Document
data "aws_iam_policy_document" "session_manager" {
  statement {
    effect = "Allow"

    actions = [
      "ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel"
    ]

    resources = [
      "*",
    ]
  }
}

# Policy allowing Vault to access SecretsManager  Needed because each Vault instance needs TLS.  Only way to dynamically fetch that every time a new instance comes up is to store the TLS Key and Cert somwhere any instance can reach.
resource "aws_iam_role_policy" "secrets_manager" {
  count  = var.vault_role_name != null ? 0 : 1
  name   = "${var.resource_name_prefix}-vault-secrets-manager"
  role   = aws_iam_role.instance_role[0].id
  policy = data.aws_iam_policy_document.secrets_manager.json
}

data "aws_iam_policy_document" "secrets_manager" {
  statement {
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
    ]

    resources = [

      var.secrets_manager_arn != null? var.secrets_manager_arn : aws_secretsmanager_secret.tls.arn
    ]
  }
}
