# Reusable AWS server fleet for a Splunk lab

Terraform provisions a private VPC, three subnets, SSM endpoints, IAM instance profiles, role-based security groups, and a configurable EC2 fleet. The example creates **11 instances** (1 cluster manager, 1 deployer, 3 indexers, 3 search heads, 1 deployment server, 2 universal forwarder hosts). The example t3.medium instances have 2 vCPUs and 4 GiB RAM; root EBS is encrypted gp3 at 40 GiB. **This provisions infrastructure only: no Splunk software, licenses, clustering configuration or Ansible playbooks are installed.** It is a lab starting point; size real Splunk workloads separately.

## Before first run

Install Terraform >= 1.10 and AWS CLI v2. Check AWS account access with `aws sts get-caller-identity`. Use AWS IAM Identity Center/temporary credentials or a CI role. The provider checks `aws\_account\_id` against the authenticated account; it does not store or assume any credentials. Pick a supported region and three available AZs. Verify EC2 quotas and expected cost (11 running instances, 11 EBS volumes and three SSM interface endpoints). The private subnet has **no NAT or internet route**. SSM works over VPC endpoints; download Splunk artifacts through an approved private path (for example, an S3 artifact bucket with endpoint access), or add controlled egress separately. Private web access requires your VPN/Direct Connect plus routing to the VPC; putting a CIDR in `admin\_cidrs` alone does not create a connection.

Create a separate S3 state bucket before initialization. Enable bucket versioning, block public access, default encryption, restricted access, and deny insecure transport; use a dedicated IAM policy permitting Terraform state object and `.tflock` operations. The state backend authenticates separately from the AWS provider; make sure the same credentials can access it. A bootstrap example:

```bash
aws s3api create-bucket --bucket splunk --region ap-south-1 --create-bucket-configuration LocationConstraint=ap-south-1
aws s3api put-public-access-block --bucket splunk --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-versioning --bucket splunk --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket splunk --server-side-encryption-configuration '{"Rules":\[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
```

Complete your organization's bucket policy/IAM restrictions before use. Do not create infrastructure in the wrong account or apply an unreviewed plan.

## Configure and deploy

```bash
cp requirements.tfvars.example requirements.tfvars
cp backend.hcl.example backend.hcl
# Edit both files: account ID, region, available AZs, CIDRs, bucket and state key.
terraform init -backend-config=backend.hcl
terraform fmt -recursive
terraform validate
terraform plan -var-file=requirements.tfvars -out=change.tfplan
terraform show change.tfplan
terraform apply change.tfplan
terraform output -raw ansible\_inventory\_json > inventory.json
```

`requirements.tfvars`, `backend.hcl`, state and plan files are ignored by Git. Commit `.terraform.lock.hcl` after `init`. Use `terraform plan -var-file=requirements.tfvars -out=change.tfplan` again whenever requirements change; inspect and apply the new plan. Run `terraform destroy -var-file=requirements.tfvars` only when intentionally tearing down the entire stack. A sample Ansible inventory is emitted, but private hosts need SSM based connection tooling or private network connectivity; conventional SSH is not configured.

## Changing the fleet

Each map key is a role and each role count produces stable `role-01`, `role-02`, ... Terraform uses `for\_each`; changing `indexer.count` from 3 to 5 adds indexer-04 and -05. Add an `ansible` role by appending:

```hcl
ansible = {
  count = 2, instance\_type = "t3.medium", disk\_gb = 40
  ports = \[{ port = 8000, admin\_cidrs = true }]
}
```

Only include a port if a daemon actually listens on it. A port entry creates **ingress on the destination role**, not a listener, and the default example includes 8000/8089/9997 as requested even where UF normally initiates traffic outbound and does not listen on 9997. `source\_roles` reference security groups, so all role names must exist. `admin\_cidrs=true` grants the listed restricted CIDRs. Empty `admin\_cidrs` creates no corresponding rules. Never use public CIDR `0.0.0.0/0`. Splunk clustering may need additional ports and bidirectional rules (the example includes SHC 8191); validate actual data flows and TLS configuration before installing. No ALB, DNS, peer discovery, or Splunk cluster bootstrap is included.

## Secrets and state

Keep AWS credentials and actual Splunk/ServiceNow secrets out of Git, Terraform variables, user data, outputs and state. Put existing Secrets Manager **ARNs** in `secret\_arns` to allow EC2 instances to fetch those values at runtime using the attached IAM profile. Provide KMS decrypt permission if a secret uses a customer-managed KMS key. The sample shares one instance profile across all roles, so for production split IAM policies by role and narrow secret ARNs. Terraform state is sensitive and protected by the S3 backend. AWS Session Manager replaces inbound SSH for administrative access. `ssm`, `ssmmessages`, `ec2messages` endpoints have hourly charges; verify regional support. The VPC S3 gateway endpoint allows S3 network access, subject to IAM/bucket policy. Existing enterprise networks can replace the self-contained VPC layer with supplied VPC/subnet IDs.

## Reference docs

* [Terraform S3 backend and S3 lockfile](https://developer.hashicorp.com/terraform/language/backend/s3)
* [AWS Systems Manager VPC endpoints](https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-create-vpc.html)
* [AWS EC2 instance types](https://docs.aws.amazon.com/ec2/latest/instancetypes/instance-types.html)

