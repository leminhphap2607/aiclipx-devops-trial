variable "aws_region" {
  default = "ap-southeast-1"
}

variable "cluster_name" {
  default = "aiclipx"
}

variable "service_name" {
  default = "aiclipx-staging"
}

variable "container_name" {
  default = "aiclipx-staging"
}

variable "image_url" {
  description = "Docker image from ECR"
}

variable "task_cpu" {
  default = 1024
}

variable "task_memory" {
  default = 3072
}
