data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

locals {
  # prevent_destroy must be a literal, so split the single input map into two
  protected_instances = { for k, v in var.instances : k => v if v.protected }
  normal_instances    = { for k, v in var.instances : k => v if !v.protected }

  common_tags = {
    Environment = var.environment
    Owner       = var.owner
  }
}

# One key pair per instance. The private key lives in state (sensitive output below).
resource "tls_private_key" "this" {
  for_each  = var.instances
  algorithm = "ED25519"
}

resource "aws_key_pair" "this" {
  for_each   = var.instances
  key_name   = "${var.environment}-${each.key}"
  public_key = tls_private_key.this[each.key].public_key_openssh
}

resource "aws_instance" "protected" {
  for_each = local.protected_instances

  ami           = data.aws_ami.al2023.id
  instance_type = each.value.instance_type
  key_name      = aws_key_pair.this[each.key].key_name
  subnet_id     = var.subnet_id

  root_block_device {
    volume_type = each.value.volume_type
    volume_size = each.value.volume_size
    iops        = each.value.iops
  }

  tags = merge(local.common_tags, { Name = each.key })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_instance" "normal" {
  for_each = local.normal_instances

  ami           = data.aws_ami.al2023.id
  instance_type = each.value.instance_type
  key_name      = aws_key_pair.this[each.key].key_name
  subnet_id     = var.subnet_id

  root_block_device {
    volume_type = each.value.volume_type
    volume_size = each.value.volume_size
    iops        = each.value.iops
  }

  tags = merge(local.common_tags, { Name = each.key })
}

