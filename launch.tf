resource "aws_launch_template" "game_server_lt" {
  depends_on    = [aws_eip.game_server_eip]
  ebs_optimized = "false"
  image_id      = data.aws_ami.amazon_linux_2023.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.game_server_key.id
  name          = "valheim-server-lt"
  user_data = base64encode(templatefile("${path.module}/scripts/userdata.sh", {
    EIP_ALLOC   = aws_eip.game_server_eip.id
    SERVER_NAME = var.SERVER_NAME
    WORLD_NAME  = var.WORLD_NAME
    SERVER_PASS = var.SERVER_PASS
    STEAM_ID    = var.STEAM_ID
    AWS_REGION  = local.aws_region
    S3_REGION   = var.S3_REGION
    S3_URI      = var.S3_URI
  }))
  vpc_security_group_ids = [
    aws_security_group.game_server_sg.id
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
    arn = aws_iam_instance_profile.game_server_instance_profile.arn
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

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-*"]
  }
  filter {
    name   = "owner-id"
    values = ["137112412989"] # Amazon's AWS account ID
  }
  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}
