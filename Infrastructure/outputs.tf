output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "service_name" {
  value = aws_ecs_service.service.name
}
output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}
