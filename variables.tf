# -----------------------------------------------------------------------------
# ENVIRONMENT VARIABLES
# Define these secrets as environment variables
# -----------------------------------------------------------------------------

# AWS_ACCESS_KEY_ID
# AWS_SECRET_ACCESS_KEY

# -----------------------------------------------------------------------------
# PARAMETERS
# -----------------------------------------------------------------------------

variable "region" {
  description = "Region to deploy"
  default     = "us-east-1"
}

variable "rds_whitelist_sg" {
  description = "Whitelist security group to add to rds"
  default     = ""
}

variable "rds_whitelist_lambda_sg" {
  description = "Whitelist security group to add to rds"
  default     = ""
}

variable "domain" {
  description = "Domain name. Service will be deployed using the hasura_subdomain"
}

variable "execution_role_arn" {
  description = "the role that the ecs task needs to execute"
}

variable "vpc_id" {
  description = "The Subdomain for your hasura graphql service."
}

variable "hasura_task_cpu" {
  description = "The task cpu"
}

variable "hasura_task_memory" {
  description = "The task memory"
}

variable "hasura_container_cpu" {
  description = "The cpu in the ecs container"
}

variable "hasura_container_memory" {
  description = "The memory in the ecs container"
}

variable "alarm_sns_topics" {
  description = "the arn to alert to"
}

variable "max_capacity" {
  description = "max capacity of hasura"
}


variable "min_capacity" {
  description = "min capacity of hasura"
}



variable "hasura_subdomain" {
  description = "The Subdomain for your hasura graphql service."
  default     = "hasura"
}

variable "app_domain" {
  description = "The Subdomain for your application that will make CORS requests to the hasura_subdomain"
  default     = "app"
}

variable "hasura_version_tag" {
  description = "The hasura graphql engine version tag"
  default     = "v1.0.0"
}

variable "hasura_admin_secret" {
  description = "The admin secret to secure hasura; for admin access"
}

variable "hasura_jwt_secret_key" {
  description = "The secret shared key for JWT verification"
}

variable "hasura_jwt_secret_algo" {
  description = "The algorithm for JWT verification (HS256 or RS256)"
  default     = "HS256"
}

variable "hasura_console_enabled" {
  description = "Should the Hasura Console web interface be enabled?"
  default     = "true"
}

variable "rds_engine_version" {
  description = "The version for RDS"
  default = "14.4"
}

variable "rds_param_group" {
  description = "The param group for RDS"
  default = "postgres14"
}

variable "rds_username" {
  description = "The username for RDS"
}

variable "rds_password" {
  description = "The password for RDS"
}

variable "rds_db_name" {
  description = "The DB name in the RDS instance"
}

variable "rds_instance" {
  description = "The size of RDS instance, eg db.t2.micro"
}

variable "rds_storage_encrypted" {
  description = "Whether the data on the PostgreSQL instance should be encrpyted."
  default     = false
}

variable "az_count" {
  description = "How many AZ's to create in the VPC"
  default     = 2
}

variable "multi_az" {
  description = "Whether to deploy RDS and ECS in multi AZ mode or not"
  default     = true
}

variable "vpc_enable_dns_hostnames" {
  description = "A boolean flag to enable/disable DNS hostnames in the VPC. Defaults false."
  default     = false
}

variable "private_subnet_ids" {
  description = "The admin secret to secure hasura; for admin access"
}


variable "public_subnet_ids" {
  description = "The admin secret to secure hasura; for admin access"
}


variable "environment" {
  description = "Environment variables for ECS task: [ { name = \"foo\", value = \"bar\" }, ..]"
  default     = []
}

variable "additional_db_security_groups" {
  description = "List of Security Group IDs to have access to the RDS instance"
  default     = []
}

variable "create_iam_service_linked_role" {
  description = "Whether to create IAM service linked role for AWS ElasticSearch service. Can be only one per AWS account."
  default     = true
}

variable "ecs_cluster_name" {
  description = "The name to assign to the ECS cluster"
  default     = "hasura-cluster"
}
