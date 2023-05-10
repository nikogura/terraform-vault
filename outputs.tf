# Outputs from the module

# VAULT_ADDR to be set by clients.
output "VAULT_ADDR" {
  value = "https://${aws_lb.vault_lb.dns_name}:8200"
}

# TLS Secret in Secret Manager - output just for reference in case you want to check it manually.
output "server_tls_secret" {
  value = aws_secretsmanager_secret.tls.arn
}

# TLS Cert in Certificate Manager - output just for reference in case you want to check it manually.
output "lb_tls_cert" {
  value = aws_acm_certificate.vault.arn
}

output "private_ca_certificate_pem" {
  value = tls_self_signed_cert.ca.cert_pem
}