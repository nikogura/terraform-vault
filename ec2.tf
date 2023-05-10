# File contains TF resources directly related to running and accessing EC2 instances running Vault
# Autodetect Latest Ubuntu Image
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

# Security Group for Vault Instances
resource "aws_security_group" "vault" {
  name   = "${var.resource_name_prefix}-vault"
  vpc_id = local.vpc_id

  tags = merge(
    { Name = "${var.resource_name_prefix}-vault-sg" },
    var.common_tags,
  )
}

# Allows traffic on port 8200 between Vault instances
resource "aws_security_group_rule" "vault_internal_api" {
  description       = "Allow Vault nodes to reach other on port 8200 for API"
  security_group_id = aws_security_group.vault.id
  type              = "ingress"
  from_port         = 8200
  to_port           = 8200
  protocol          = "tcp"
  self              = true
}

# Allows traffic on 8201 between Vault instances. This is Vault's internal gossip traffic to keep the cluster in sync
resource "aws_security_group_rule" "vault_internal_raft" {
  description       = "Allow Vault nodes to communicate on port 8201 for replication traffic, request forwarding, and Raft gossip"
  security_group_id = aws_security_group.vault.id
  type              = "ingress"
  from_port         = 8201
  to_port           = 8201
  protocol          = "tcp"
  self              = true
}


# This resource looks up the internal or private subnets - we only want to put Vault in an internal network.
data "aws_subnet" "vault" {
  for_each = toset(data.aws_subnets.private.ids)
  id       = each.value
}

# Generate a list of cidr blocks for the subnets based on the results of the resource above
locals {
  vault_subnet_cidr_blocks = [for s in data.aws_subnet.vault : s.cidr_block]
}

# Security group to allow inbound Vault client traffic through the load balancer
resource "aws_security_group_rule" "vault_network_lb_inbound" {
  count             = var.lb_type == "network" ? 1 : 0
  description       = "Allow load balancer to reach Vault nodes on port 8200"
  security_group_id = aws_security_group.vault.id
  type              = "ingress"
  from_port         = 8200
  to_port           = 8200
  protocol          = "tcp"
  cidr_blocks       = local.vault_subnet_cidr_blocks
}

# Allows traffic from Load Balancer to Vault instances
resource "aws_security_group_rule" "vault_application_lb_inbound" {
  count                    = var.lb_type == "application" ? 1 : 0
  description              = "Allow load balancer to reach Vault nodes on port 8200"
  security_group_id        = aws_security_group.vault.id
  type                     = "ingress"
  from_port                = 8200
  to_port                  = 8200
  protocol                 = "tcp"
  source_security_group_id = var.lb_type == "application" ? aws_security_group.vault_lb[0].id : null
}

# Allows access to LB and nodes
resource "aws_security_group_rule" "vault_network_lb_ingress" {
  count             = var.lb_type == "network" && var.allowed_inbound_cidrs_lb != null ? 1 : 0
  description       = "Allow specified CIDRs access to load balancer and nodes on port 8200"
  security_group_id = aws_security_group.vault.id
  type              = "ingress"
  from_port         = 8200
  to_port           = 8200
  protocol          = "tcp"
  cidr_blocks       = var.allowed_inbound_cidrs_lb
}

# Allows SSH to the vault nodes - only has an effect if you specify var.allowed_cidrs_ssh
resource "aws_security_group_rule" "vault_ssh_inbound" {
  count             = var.allowed_inbound_cidrs_ssh != null ? 1 : 0
  description       = "Allow specified CIDRs SSH access to Vault nodes"
  security_group_id = aws_security_group.vault.id
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = var.allowed_inbound_cidrs_ssh
}

# Open outbound traffic from Vault instances.
resource "aws_security_group_rule" "vault_outbound" {
  description       = "Allow Vault nodes to send outbound traffic"
  security_group_id = aws_security_group.vault.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

# Launch template for Vault instances
resource "aws_launch_template" "vault" {
  name          = "${var.resource_name_prefix}-vault"
  image_id      = var.vault_ami_id != null ? var.vault_ami_id : data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.ssh_key_name != null ? var.ssh_key_name : null
  user_data     = base64encode(local.vault_user_data)
  vpc_security_group_ids = [
    aws_security_group.vault.id,
  ]

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_type           = "gp3"
      volume_size           = 100
      throughput            = 150
      iops                  = 3000
      delete_on_termination = true
    }
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.vault.name
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
}

# Autoscaling group for Vault instances
resource "aws_autoscaling_group" "vault" {
  name                = "${var.resource_name_prefix}vault"
  min_size            = var.vault_node_count
  max_size            = var.vault_node_count
  desired_capacity    = var.vault_node_count
  vpc_zone_identifier = data.aws_subnets.private.ids
  target_group_arns   = [aws_lb_target_group.vault.arn]

  launch_template {
    id      = aws_launch_template.vault.id
    version = "$Latest"
  }
  instance_refresh {
    strategy = "Rolling"
  }

  # This tag merely puts a human readable name on the instance for display in the EC2 console.
  tag {
    key                 = "Name"
    value               = "${var.resource_name_prefix}-vault-server"
    propagate_at_launch = true
  }

  # This tag is used for node auto join.  Each vault server will query AWS and find servers with this tag, automatically joining the cluster on the nodes it finds.
  tag {
    key                 = "${var.resource_name_prefix}-vault"
    value               = "server"
    propagate_at_launch = true
  }

  # Optional xtra tags applied to the Vault instances
  dynamic "tag" {
    for_each = var.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}
