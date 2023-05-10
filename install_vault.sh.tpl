#!/usr/bin/env bash

# This is the Vault instance user-data script used to bootstrap each node.
# It's run once per instance on initial start
# All comments are echoed to the console, and should end up in /var/log/cloud-init-output.log

echo "Querying the EC2 metadata services for data about this instance"
imds_token=$( curl -Ss -H "X-aws-ec2-metadata-token-ttl-seconds: 30" -XPUT 169.254.169.254/latest/api/token )
instance_id=$( curl -Ss -H "X-aws-ec2-metadata-token: $imds_token" 169.254.169.254/latest/meta-data/instance-id )
local_ipv4=$( curl -Ss -H "X-aws-ec2-metadata-token: $imds_token" 169.254.169.254/latest/meta-data/local-ipv4 )

echo "Adding Hashicorp repo keys to trust store"
curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add -

echo "Adding Hashicorp repository"
apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"

echo "Updating the package cache"
apt-get update

echo "Installing vault, awscli, and jq"
apt-get install -y vault=${vault_version} awscli jq

echo "Configuring system time"
timedatectl set-timezone UTC

echo "Removing any default installation files from /opt/vault/tls/"
rm -rf /opt/vault/tls/*

echo "Chmod 0755 /opt/vault/tls - should be readable by all users of the system"
chmod 0755 /opt/vault/tls

echo "vault-key.pem should be readable by the vault group only"
touch /opt/vault/tls/vault-key.pem
chown root:vault /opt/vault/tls/vault-key.pem
chmod 0640 /opt/vault/tls/vault-key.pem

echo "Pulling TLS material from SecretsManager with command: 'aws secretsmanager get-secret-value --secret-id ${secrets_manager_arn} --region ${region} --output text --query SecretString'"
secret_result=$(aws secretsmanager get-secret-value --secret-id ${secrets_manager_arn} --region ${region} --output text --query SecretString)

echo "Parsing secret value with jq"

jq -r .vault_cert <<< "$secret_result" | base64 -d > /opt/vault/tls/vault-cert.pem

jq -r .vault_ca <<< "$secret_result" | base64 -d > /opt/vault/tls/vault-ca.pem

jq -r .vault_pk <<< "$secret_result" | base64 -d > /opt/vault/tls/vault-key.pem

echo "Writing vault ocnfig file to /etc/vault.d/vault.hcl"

cat << EOF > /etc/vault.d/vault.hcl
disable_performance_standby = true
ui = true
disable_mlock = true

storage "raft" {
  path    = "/opt/vault/data"
  node_id = "$instance_id"
  retry_join {
    auto_join = "provider=aws region=${region} tag_key=${name}-vault tag_value=server"
    auto_join_scheme = "https"
    leader_tls_servername = "${leader_tls_servername}"
    leader_ca_cert_file = "/opt/vault/tls/vault-ca.pem"
    leader_client_cert_file = "/opt/vault/tls/vault-cert.pem"
    leader_client_key_file = "/opt/vault/tls/vault-key.pem"
  }
}

cluster_addr = "https://$local_ipv4:8201"
api_addr = "https://$local_ipv4:8200"

listener "tcp" {
  address            = "0.0.0.0:8200"
  tls_disable        = false
  tls_cert_file      = "/opt/vault/tls/vault-cert.pem"
  tls_key_file       = "/opt/vault/tls/vault-key.pem"
  tls_client_ca_file = "/opt/vault/tls/vault-ca.pem"
}

seal "awskms" {
  region     = "${region}"
  kms_key_id = "${kms_key_arn}"
}

EOF

echo "vault.hcl should be readable by the vault group only"
chown root:root /etc/vault.d
chown root:vault /etc/vault.d/vault.hcl
chmod 640 /etc/vault.d/vault.hcl

echo "Enabling and starting vault"
systemctl enable vault
systemctl start vault

echo "Setup Vault profile"
cat <<PROFILE | sudo tee /etc/profile.d/vault.sh
export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_CACERT="/opt/vault/tls/vault-ca.pem"
PROFILE

echo "done with cloud-init"