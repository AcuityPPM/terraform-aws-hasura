output "ecs_security_group" {
  description = "Security group controlling access to the ECS tasks"
  value = aws_security_group.hasura_ecs
}
