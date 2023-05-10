# Terraform for Hashicorp Vault

Shamelessly copied from https://github.com/hashicorp/terraform-aws-vault-starter and flattened into a single module.

Hashicorp's preferred module structure makes for hierarchies of resources and internal modules.  They then  pass variables around up and down the call stack sometimes reusing variable names, and other times making wholly new and redundant names.  It makes for a 'reference implementation' that can be really difficult to understand and trace errors.  

By flattening Hashicorp's offering it is hoped that we can make it extremely obvious what's going on.  At its heart, Vault on AWS is simply a set of EC2 instances behind a load balancer that have the ability to share information amongst themselves in the background.

In the past, Hashicorp's recommendation for running Vault was to use Consul as the storage layer.  This worked well, but in order to run Vault, you also had to understand how to run Consul. New versions of Vault build the raft-based storage of Consul directly into Vault, eliminating the need for a separate storage layer.

At the time of this writing, running Vault with 'Internal Raft Storage' is the recommended means of running Vault in production.

# TLS

It's possible to run Vault without transport encryption.  Doing so actually solves a lot of initial setup problems.  Vault however, is a security service, and therefore it really doesn't like doing so outside of 'dev mode'.  Again, _possible_, but there are many issues.

To combat this problem, this module automatically creates a self-generated CA (Certificate Authority), and signed TLS Certificates and Keys to provide transport level encryption for traffic between Vault instances.  This module provisions them in AWS SecretsManager and CertificateManager where the Vault instances and Load Balancers can find them.  Vault is then configured to trust these certificates.

As a default, this private CA certificate is placed on the TLS listener for the Vault Load Balancer.  Vault instances will automatically trust this certificate because this module configures them to do so.  Your clients on the other hand, will not.

In order for your clients to trust this generated Certificate Authority, this module will output the CA cert PEM.

To install it on an Ubuntu machine, perform the following steps:

1. Copy the PEM including the '-----BEGIN CERTIFICATE-----' and '-----END CERTIFICATE-----' lines.
2. Paste the above content into the file `/usr/local/share/ca-certificates/vault-ca.crt`.
3. Run `sudo update-ca-certificates`.

The file location and command will vary for other OS versions.  Consult the internet or your local `man` pages for details for your OS.

By default, the CA certificate, and the server certificate and private key are stored in AWS SecretsManager, and placed on each Vault instance via userdata
store tls in SecretsManager for adding to instances when they initially start.

The cert is also imported into Amazon Certificate Manager to be used on the TLS listener.

# TODO

* Expand outputs
* Add Vault config terraform?
* Ensure that TLS resources are optional
* Provide for importation of key material for instance to instance TLS