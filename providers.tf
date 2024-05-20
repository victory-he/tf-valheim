terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.57.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

terraform {
  backend "s3" {
    bucket = "valheim-sigr-2"
    key    = "tf-state/terraform.tfstate"
    region = "us-west-2"
  }
}
