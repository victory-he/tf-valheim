resource "aws_vpc" "tf-valheim-vpc" {
  cidr_block       = "10.51.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "tf-valheim-vpc"
  }
}

resource "aws_subnet" "tf-valheim-sn" {
  vpc_id                  = aws_vpc.tf-valheim-vpc.id
  cidr_block              = "10.51.6.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "tf-valheim-sn"
  }
}

resource "aws_internet_gateway" "tf-valheim-igw" {
  vpc_id = aws_vpc.tf-valheim-vpc.id
  tags = {
    Name = "tf-valheim-igw"
  }
}

resource "aws_route_table" "tf-valheim-rt" {
  vpc_id = aws_vpc.tf-valheim-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.tf-valheim-igw.id
  }

  tags = {
    Name = "tf-valheim-rt"
  }
}

resource "aws_route_table_association" "tf-valheim-rt-assoc" {
  subnet_id      = aws_subnet.tf-valheim-sn.id
  route_table_id = aws_route_table.tf-valheim-rt.id
}

resource "aws_security_group" "tf-valheim-sg" {
  name        = "tf-valheim-sg"
  description = "Allow SSH and UDP"
  vpc_id      = aws_vpc.tf-valheim-vpc.id

  ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "UDP from VPC"
    from_port   = 2456
    to_port     = 2457
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "valheim-sg"
  }
}

data "aws_region" "current" {}

locals {
  timestamped_tag = "${var.instance_tag}-${timestamp()}"
  aws_region      = data.aws_region.current.name
}

resource "aws_launch_template" "tf-valheim-lt" {
  depends_on    = [aws_eip.valheim-eip]
  ebs_optimized = "false"
  image_id      = "ami-079db87dc4c10ac91"
  instance_type = "t3a.medium"
  key_name      = var.key_name
  name          = "tf-valheim-lt"
  user_data = base64encode(templatefile("${path.module}/scripts/userdata.sh", {
    EIP_ALLOC   = aws_eip.valheim-eip.id
    SERVER_NAME = var.SERVER_NAME
    WORLD_NAME  = var.WORLD_NAME
    SERVER_PASS = var.SERVER_PASS
    STEAM_ID    = var.STEAM_ID
    AWS_REGION  = local.aws_region
    S3_REGION   = var.S3_REGION
    S3_URI      = var.S3_URI
  }))
  vpc_security_group_ids = [
    aws_security_group.tf-valheim-sg.id
  ]

  credit_specification {
    cpu_credits = "unlimited"
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      delete_on_termination = "true"
      encrypted             = "false"
      volume_size           = 20
      volume_type           = "gp3"
    }
  }

  iam_instance_profile {
    arn = var.instance_profile_arn
  }

  instance_market_options {
    market_type = "spot"

    spot_options {
      spot_instance_type = "one-time"
    }
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = local.timestamped_tag
    }
  }
}

resource "aws_autoscaling_group" "tf-valheim-asg" {
  desired_capacity    = 1
  max_size            = 1
  min_size            = 1
  vpc_zone_identifier = [aws_subnet.tf-valheim-sn.id]

  launch_template {
    id      = aws_launch_template.tf-valheim-lt.id
    version = "$Latest"
  }
  depends_on = [aws_eip.valheim-eip]
}

resource "aws_eip" "valheim-eip" {
  vpc              = true
  public_ipv4_pool = "amazon"
  depends_on       = [aws_internet_gateway.tf-valheim-igw]
  tags = {
    Name = local.timestamped_tag
  }
}

data "aws_instance" "valheim" {
  filter {
    name   = "tag:Name"
    values = [local.timestamped_tag]
  }
  depends_on = [aws_autoscaling_group.tf-valheim-asg]
}

resource "aws_eip_association" "eip_assoc" {
  instance_id   = data.aws_instance.valheim.id
  allocation_id = aws_eip.valheim-eip.id
}
