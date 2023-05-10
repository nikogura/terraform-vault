# Load Balancing Resources
# Vault can use an Application or Network Load balancer depending on your preference.

#  Security group that allows access to the load balancer.  Only clients in this SG will be able to connect to vault
resource "aws_security_group" "vault_lb" {
  count       = var.lb_type == "application" ? 1 : 0
  description = "Security group for the application load balancer"
  name        = "${var.resource_name_prefix}-vault-lb-sg"
  vpc_id      = local.vpc_id

  tags = merge(
    { Name = "${var.resource_name_prefix}-vault-lb-sg" },
    var.common_tags,
  )
}

# Rule allowing inbound traffic on prot 8200 to the load balancer.
resource "aws_security_group_rule" "vault_lb_inbound" {
  count             = var.lb_type == "application" && var.allowed_inbound_cidrs_lb != null ? 1 : 0
  description       = "Allow specified CIDRs access to load balancer on port 8200"
  security_group_id = aws_security_group.vault_lb[0].id
  type              = "ingress"
  from_port         = 8200
  to_port           = 8200
  protocol          = "tcp"
  cidr_blocks       = var.allowed_inbound_cidrs_lb
}

# Rule allowing outbound traffic through the load balancer
resource "aws_security_group_rule" "vault_lb_outbound" {
  count                    = var.lb_type == "application" ? 1 : 0
  description              = "Allow outbound traffic from load balancer to Vault nodes on port 8200"
  security_group_id        = aws_security_group.vault_lb[0].id
  type                     = "egress"
  from_port                = 8200
  to_port                  = 8200
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.vault.id
}

# Local variables to deal with the Application/Network load balancer duality.  The resources require slightly different configuration.
locals {
  lb_security_groups = var.lb_type == "network" ? null : [aws_security_group.vault_lb[0].id]
  lb_protocol        = var.lb_type == "network" ? "TCP" : "HTTPS"
}

# The actual Vault Load Balancer
resource "aws_lb" "vault_lb" {
  name                       = "${var.resource_name_prefix}vault-lb"
  internal                   = var.internal_lb
  load_balancer_type         = var.lb_type
  subnets                    = data.aws_subnets.private.ids  # data source returns a list of subnet ID's
  security_groups            = local.lb_security_groups
  drop_invalid_header_fields = var.lb_type == "application" ? true : null

  tags = merge(
    { Name = "${var.resource_name_prefix}-vault-lb" },
    var.common_tags,
  )
}

# Target Group for the Vault Load Balancer.  The members of this TG will be the Vault EC2 instances.
resource "aws_lb_target_group" "vault" {
  name        = "${var.resource_name_prefix}vault-tg"
  target_type = "instance"
  port        = 8200
  protocol    = local.lb_protocol
  vpc_id      = local.vpc_id

  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 3
    protocol            = "HTTPS"
    port                = "traffic-port"
    path                = var.vault_healthcheck_path
    interval            = 30
  }

  tags = merge(
    { Name = "${var.resource_name_prefix}-vault-tg" },
    var.common_tags,
  )
}

# Listener for the Vault LB.  Can work without TLS, but it's really not advised.
resource "aws_lb_listener" "vault" {
  load_balancer_arn = aws_lb.vault_lb.id
  port              = 8200
  protocol          = local.lb_protocol
  ssl_policy        = local.lb_protocol == "HTTPS" ? var.ssl_policy : null
  certificate_arn   = local.lb_protocol == "HTTPS" ? var.vault_lb_certificate_arn != null ? var.vault_lb_certificate_arn : aws_acm_certificate.vault.arn : null

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vault.arn
  }
}
