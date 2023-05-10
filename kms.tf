# KMS Resources

# KMS Key for encrypting and decrypting Vault Master key.  Everything stored in Vault is encrypted.  The decrypted master key is only ever stored in memory in each Vault instance.  That key must be stored somewhere outside of vault for each new vault instance to be able to retrieve it upon initial start.  The key below exists to provide this ability.
resource "aws_kms_key" "vault" {
  count                   = var.kms_key_arn != null ? 0 : 1
  deletion_window_in_days = var.kms_deletion_window_days
  description             = "AWS KMS Customer-managed key used for Vault auto-unseal and encryption"
  enable_key_rotation     = false
  is_enabled              = true
  key_usage               = "ENCRYPT_DECRYPT"

  tags = merge(
    { Name = "${var.resource_name_prefix}-vault-key" },
    var.common_tags,
  )
}
