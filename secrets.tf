# Random string to interpolate into resources when the default lifecycle takes time to delete (Secrets, KMS Keys, etc)  Facilitates rapid 'nuke and pave' testing.
resource "random_string" "tls" {
  length = 10
  special = false
}

# A secret that will contain the self-signed TLS Key and Certificate for provisioning on Vault servers.
resource "aws_secretsmanager_secret" "tls" {
  name                    = "${var.resource_name_prefix}${random_string.tls.result}tls-secret"
  description             = "contains TLS certs and private keys"
  kms_key_id              =  var.kms_key_arn != null? var.kms_key_arn : aws_kms_key.vault[0].arn
}

# The actual value of the self-signed TLS
resource "aws_secretsmanager_secret_version" "tls" {
  secret_id     = aws_secretsmanager_secret.tls.id
  secret_string = local.secret
}