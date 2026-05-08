terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.6.2"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.5.1"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.0.4"
    }
  }
  cloud {
    organization = "Sane"
    workspaces {
      name = "instance"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "random_shuffle" "selected_azs" {
  input        = data.aws_availability_zones.available.names
  result_count = 2
}

variable "allowed_ports" {
  description = "Public TCP ports to expose. SSH is restricted by allowed_ssh_cidrs."
  type        = list(number)
  default = [
    22,
    80,
    443,
    5678
  ]
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to reach SSH. Override this with your current public IP for production use."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "aws_region" {
  description = "AWS region used for all resources."
  type        = string
  default     = "us-east-1"
}

locals {
  ssh_ports     = contains(var.allowed_ports, 22) ? toset([22]) : toset([])
  non_ssh_ports = toset([for port in var.allowed_ports : port if port != 22])
}

data "aws_ami" "ubuntu_latest_arm" {
  most_recent = true

  owners = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-noble-24.04-arm64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.0.1"

  name = "app-vpc"

  azs             = random_shuffle.selected_azs.result
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = false
  enable_vpn_gateway = false

  tags = {
    Terraform   = "true"
    Environment = "dev"
    CreatedBy   = "Terraform"
  }
}

resource "aws_security_group" "allowed_ports" {
  name        = "${module.vpc.name}-allowed_ports"
  description = "Allowed ingress ports"
  vpc_id      = module.vpc.vpc_id

  dynamic "ingress" {
    for_each = local.ssh_ports
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = var.allowed_ssh_cidrs
      description = "SSH access"
    }
  }

  dynamic "ingress" {
    for_each = local.non_ssh_ports
    content {
      from_port        = ingress.value
      to_port          = ingress.value
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
      description      = "Public TCP ${ingress.value}"
    }
  }
  tags = {
    Name        = "${module.vpc.name}-allowed_ports"
    Terraform   = "true"
    Environment = "dev"
    CreatedBy   = "Terraform"
  }

}

resource "aws_security_group" "all_outbound" {
  name        = "${module.vpc.name}-allow-outbound"
  description = "Allow All Outbound traffic"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = -1
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
    description      = "Allow all outbound traffic"
  }

  tags = {
    Name        = "${module.vpc.name}-allow-outbound"
    Terraform   = "true"
    Environment = "dev"
    CreatedBy   = "Terraform"
  }
}


module "ec2_instance" {
  source = "terraform-aws-modules/ec2-instance/aws"

  name = "free-instance"

  ami = data.aws_ami.ubuntu_latest_arm.id

  instance_type = "t4g.small"
  key_name      = "Local"
  subnet_id     = module.vpc.public_subnets[0]
  vpc_security_group_ids = [
    aws_security_group.allowed_ports.id,
    aws_security_group.all_outbound.id
  ]

  associate_public_ip_address = true

  user_data = <<-EOF
     #!/bin/bash
     set -eux
     apt-get update
     apt-get install -y ca-certificates curl gnupg lsb-release
     install -m 0755 -d /etc/apt/keyrings
     curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
     chmod a+r /etc/apt/keyrings/docker.gpg
     echo "deb [arch=arm64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" >/etc/apt/sources.list.d/docker.list
     apt-get update
     apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
     groupadd -f docker
     usermod -aG docker ubuntu
     systemctl enable --now docker
     apt-get upgrade -y
   EOF

  tags = {
    Name        = "free-instance"
    Terraform   = "true"
    Environment = "dev"
  }
}

output "instance_public_ip" {
  value = module.ec2_instance.public_ip
}
