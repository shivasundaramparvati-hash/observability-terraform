data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
resource "aws_iam_role" "instance" {
  name_prefix = "${var.project_name}-${var.environment}-ec2-"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy" "secrets" {
  count = length(var.secret_arns) > 0 ? 1 : 0
  name  = "runtime-secrets"
  role  = aws_iam_role.instance.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = var.secret_arns }] })
}
resource "aws_iam_instance_profile" "instance" {
  name_prefix = "${var.project_name}-${var.environment}-"
  role        = aws_iam_role.instance.name
}
module "servers" {
  source   = "./modules/ec2-server"
  for_each = local.instances
  name     = "${var.project_name}-${var.environment}-${each.key}"
  role     = each.value.role
  ami      = data.aws_ami.al2023.id
  instance_type        = each.value.instance_type
  disk_gb              = each.value.disk_gb
  subnet_id            = aws_subnet.private[each.value.subnet_key].id
  security_group_id    = aws_security_group.role[each.value.role].id
  instance_profile     = aws_iam_instance_profile.instance.name
  depends_on           = [aws_iam_role_policy_attachment.ssm, aws_vpc_endpoint.ssm]
}
