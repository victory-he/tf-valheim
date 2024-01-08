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

variable "instance_profile_arn" {
  type = string
}

variable "instance_tag" {
  type    = string
  default = "valheim-tf"
}

variable "key_name" {
  type = string
}
