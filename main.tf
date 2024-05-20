resource "aws_key_pair" "game_server_key" {
  key_name   = "game_server_key"
  public_key = var.public_key
}

resource "aws_vpc" "game_server_vpc" {
  cidr_block       = var.vpc_cidr_block
  instance_tenancy = "default"
  tags = {
    Name = "game_server_vpc"
  }
}

resource "aws_subnet" "game_server_sn" {
  vpc_id                  = aws_vpc.game_server_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.game_server_vpc.cidr_block, 4, 1)
  map_public_ip_on_launch = true

  tags = {
    Name = "game_server_sn"
  }
}

resource "aws_internet_gateway" "game_server_igw" {
  vpc_id = aws_vpc.game_server_vpc.id
  tags = {
    Name = "game_server_igw"
  }
}

resource "aws_route_table" "game_server_rt" {
  vpc_id = aws_vpc.game_server_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.game_server_igw.id
  }

  tags = {
    Name = "game_server_rt"
  }
}

resource "aws_route_table_association" "game_server_rt_assoc" {
  subnet_id      = aws_subnet.game_server_sn.id
  route_table_id = aws_route_table.game_server_rt.id
}

resource "aws_security_group" "game_server_sg" {
  name        = "game_server_sg"
  description = "Allow SSH and UDP"
  vpc_id      = aws_vpc.game_server_vpc.id

  ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "UDP from VPC"
    from_port   = var.game_port
    to_port     = var.game_port
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
    Name = "game_server_sg"
  }
}

resource "aws_iam_instance_profile" "game_server_instance_profile" {
  name = "game_server_instance_profile"
  role = aws_iam_role.game_server_role.name
}

resource "aws_iam_role" "game_server_role" {
  name = "game_server_role"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "ec2.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "game_server_policy_attach" {
  role       = aws_iam_role.game_server_role.id
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

data "aws_region" "current" {}

locals {
  timestamped_tag = "${var.instance_tag}_${timestamp()}"
  aws_region      = data.aws_region.current.name
}

resource "aws_autoscaling_group" "game_server_asg" {
  desired_capacity    = 1
  max_size            = 1
  min_size            = 1
  vpc_zone_identifier = [aws_subnet.game_server_sn.id]

  launch_template {
    id      = aws_launch_template.game_server_lt.id
    version = "$Latest"
  }
  depends_on = [aws_eip.game_server_eip]
}

resource "aws_eip" "game_server_eip" {
  #   domain           = "vpc"
  public_ipv4_pool = "amazon"
  depends_on       = [aws_internet_gateway.game_server_igw]
  tags = {
    Name = local.timestamped_tag
  }
}

data "aws_instance" "game_server" {
  filter {
    name   = "tag:Name"
    values = [local.timestamped_tag]
  }
  depends_on = [aws_autoscaling_group.game_server_asg]
}

resource "aws_eip_association" "eip_assoc" {
  instance_id   = data.aws_instance.game_server.id
  allocation_id = aws_eip.game_server_eip.id
}

data "aws_subnet" "game_server_sn" {
  id = aws_subnet.game_server_sn.id
}

# resource "aws_ebs_volume" "game_server_ebs" {
#   availability_zone = data.aws_subnet.game_server_sn.availability_zone
#   size              = 10
#   type              = "gp3"
#   tags = {
#     Name = "game_server_data"
#   }
# }

output "game_server_ip" {
  description = "Use this IP to connect to the game server!"
  value       = aws_eip.game_server_eip.public_ip
}
