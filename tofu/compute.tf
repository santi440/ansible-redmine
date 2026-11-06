resource "aws_key_pair" "redmine" {
  key_name   = "${local.name}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))

  tags = {
    Name = "${local.name}-key"
  }
}

resource "aws_instance" "redmine" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.redmine.key_name
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  associate_public_ip_address = true

  user_data = <<-EOT
    #cloud-config
    package_update: true
    packages:
      - python3-apt
      - acl
  EOT

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name = "${local.name}-app"
  }
}

resource "aws_eip" "redmine" {
  domain   = "vpc"
  instance = aws_instance.redmine.id

  tags = {
    Name = "${local.name}-eip"
  }

  depends_on = [aws_internet_gateway.redmine]
}
