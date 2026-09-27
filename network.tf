resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "${var.project_name}-${var.environment}" }
}
resource "aws_subnet" "private" {
  for_each                = var.private_subnets
  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = false
  tags = { Name = "${var.project_name}-${var.environment}-${each.key}" }
}
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-${var.environment}-private" }
}
resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}
resource "aws_security_group" "endpoints" {
  name_prefix = "${var.project_name}-${var.environment}-vpce-"
  description = "HTTPS from private VPC to Systems Manager endpoints"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.project_name}-${var.environment}-vpce" }
  lifecycle { create_before_destroy = true }
}
resource "aws_vpc_security_group_ingress_rule" "endpoint_https" {
  security_group_id = aws_security_group.endpoints.id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}
resource "aws_vpc_endpoint" "ssm" {
  for_each            = toset(["ssm", "ssmmessages", "ec2messages"])
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.endpoints.id]
  tags = { Name = "${var.project_name}-${var.environment}-${each.key}" }
}
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
  tags = { Name = "${var.project_name}-${var.environment}-s3" }
}
