output "vpc_id" { value = aws_vpc.main.id }
output "servers" {
  value = { for key, server in module.servers : key => {
    id                = server.id
    private_ip        = server.private_ip
    availability_zone = server.availability_zone
    role              = local.instances[key].role
  } }
}
output "ansible_inventory_json" {
  description = "Use terraform output -raw ansible_inventory_json > inventory.json"
  value = jsonencode(merge({
    _meta = { hostvars = { for key, server in module.servers : key => {
      ansible_host    = server.private_ip
      ansible_user    = "ec2-user"
      aws_instance_id = server.id
    } } }
    all = { children = sort(keys(var.servers)) }
  }, { for role in keys(var.servers) : role => { hosts = [for key, server in module.servers : key if local.instances[key].role == role] } }))
}
