variable "vpc_cidr_block" {
  type = string
}

variable "SERVER_NAME" {
  type = string
}

variable "WORLD_NAME" {
  type = string
}

variable "SERVER_PASS" {
  type = string
}

variable "STEAM_ID" {
  type = string
}

variable "S3_URI" {
  type = string
}

variable "S3_REGION" {
  type = string
}

variable "instance_tag" {
  type    = string
  default = "valheim-tf"
}

variable "public_key" {
  type = string
}

variable "game_port" {
  type    = string
  default = "2456"
}

variable "instance_type" {
  type = string
}
