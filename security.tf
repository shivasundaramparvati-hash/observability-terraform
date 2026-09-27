locals {
  instance_list = flatten([for role, config in var.servers : [for n in range(config.count) : {
    key           = format("%s-%02d", role, n + 1)
    role          = role
    instance_type = config.instance_type
    disk_gb       = config.disk_gb
    subnet_key    = sort(keys(var.private_subnets))[n % length(var.private_subnets)]
  }]])
  instances = { for instance in local.instance_list : instance.key => instance }
  role_rules = flatten([for role, config in var.servers : [for p in config.ports : [for source in p.source_roles : {
    key = "${role}-${p.port}-${source}", role = role, port = p.port, source = source
  }]]])
  admin_rules = flatten([for role, config in var.servers : [for p in config.ports : [for cidr in p.admin_cidrs ? var.admin_cidrs : [] : {
    key = "${role}-${p.port}-${replace(cidr, "/", "-")}", role = role, port = p.port, cidr = cidr
  }]]])
}
resource "aws_security_group" "role" {
  for_each    = var.servers
  name_prefix = "${var.project_name}-${var.environment}-${each.key}-"
  description = "Inbound rules for ${each.key}"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.project_name}-${var.environment}-${each.key}" }
  lifecycle { create_before_destroy = true }
}
resource "aws_vpc_security_group_ingress_rule" "role" {
  for_each                     = { for r in local.role_rules : r.key => r }
  security_group_id            = aws_security_group.role[each.value.role].id
  referenced_security_group_id = aws_security_group.role[each.value.source].id
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
}
resource "aws_vpc_security_group_ingress_rule" "admin" {
  for_each          = { for r in local.admin_rules : r.key => r }
  security_group_id = aws_security_group.role[each.value.role].id
  cidr_ipv4         = each.value.cidr
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
}
resource "aws_vpc_security_group_egress_rule" "outbound" {
  for_each          = var.servers
  security_group_id = aws_security_group.role[each.key].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Outbound traffic (private subnets have no default internet route)"
}
