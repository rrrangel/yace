variable "aws_region" {
  description = "AWS region"
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name"
  default     = "prod"
}

variable "app_name" {
  description = "Application name"
  default     = "yace-exporter"
}

variable "container_port" {
  description = "Container port"
  default     = 5000
}

variable "yace_version" {
  description = "YACE version to use"
  default     = "v0.27.0"
}