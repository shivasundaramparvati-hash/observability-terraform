variable "aws_account_id" {
  type = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must have 12 digits."
  }
}
variable "aws_region" { type = string }
variable "project_name" { type = string }
variable "environment" { type = string }
variable "vpc_cidr" { type = string }
variable "private_subnets" {
  type = map(object({ cidr = string, availability_zone = string }))
  validation {
    condition     = length(var.private_subnets) >= 1
    error_message = "Specify at least one private subnet."
  }
}
variable "admin_cidrs" {
  description = "Trusted VPN/corporate CIDRs permitted to reach explicitly configured web/management ports; private connectivity is required."
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for c in var.admin_cidrs : can(cidrhost(c, 0)) && c != "0.0.0.0/0"])
    error_message = "Use valid, restricted IPv4 CIDRs; 0.0.0.0/0 is forbidden."
  }
}
variable "servers" {
  type = map(object({
    count         = number
    instance_type = string
    disk_gb       = number
    ports = optional(list(object({
      port         = number
      source_roles = optional(list(string), [])
      admin_cidrs  = optional(bool, false)
    })), [])
  }))
  validation {
    condition     = alltrue([for _, s in var.servers : s.count >= 0 && floor(s.count) == s.count && s.count <= 100 && s.disk_gb >= 8])
    error_message = "Server counts must be integers between 0 and 100; root disks must be at least 8 GiB."
  }
  validation {
    condition     = alltrue(flatten([for _, s in var.servers : [for p in s.ports : p.port >= 1 && p.port <= 65535 && (length(p.source_roles) > 0 || p.admin_cidrs)]]))
    error_message = "Each port must be valid and have a source role or admin_cidrs=true."
  }
  validation {
    condition     = alltrue(flatten([for _, s in var.servers : [for p in s.ports : alltrue([for source in p.source_roles : contains(keys(var.servers), source)])]]))
    error_message = "Every source_roles entry must name an existing role in servers."
  }
  validation {
    condition     = alltrue([for _, s in var.servers : length(s.ports) == length(distinct([for p in s.ports : p.port]))])
    error_message = "Ports must be unique within each role."
  }
}
variable "secret_arns" {
  description = "Existing Secrets Manager ARNs authorized for instance runtime access. Values stay outside Terraform."
  type        = list(string)
  default     = []
}
