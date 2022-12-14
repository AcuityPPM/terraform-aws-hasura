# -----------------------------------------------------------------------------
# Create the certificate
# -----------------------------------------------------------------------------

resource "aws_acm_certificate" "hasura" {
  domain_name       = "${var.hasura_subdomain}.${var.domain}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Validate the certificate
# -----------------------------------------------------------------------------

data "aws_route53_zone" "hasura" {
  name = "${var.domain}."
}

resource "aws_route53_record" "hasura_validation" {
  depends_on = [aws_acm_certificate.hasura]
  name    = element(tolist(aws_acm_certificate.hasura.domain_validation_options), 0)["resource_record_name"]
  type    = element(tolist(aws_acm_certificate.hasura.domain_validation_options), 0)["resource_record_type"]
  zone_id = data.aws_route53_zone.hasura.zone_id
  records = [element(tolist(aws_acm_certificate.hasura.domain_validation_options), 0)["resource_record_value"]]
  ttl     = 300
}

resource "aws_acm_certificate_validation" "hasura" {
  certificate_arn         = aws_acm_certificate.hasura.arn
  validation_record_fqdns = aws_route53_record.hasura_validation.*.fqdn
}

# -----------------------------------------------------------------------------
# Create security groups
# -----------------------------------------------------------------------------

# Internet to ALB
resource "aws_security_group" "hasura_alb" {
  name       = "${var.rds_db_name}-alb"
  description = "Allow access on port 443 only to ALB"
  vpc_id      = var.vpc_id

  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ALB TO ECS
resource "aws_security_group" "hasura_ecs" {
  name       = "${var.rds_db_name}-tasks"
  description = "allow inbound access from the ALB only"
  vpc_id      = var.vpc_id

  ingress {
    protocol        = "tcp"
    from_port       = "8080"
    to_port         = "8080"
    security_groups = [aws_security_group.hasura_alb.id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ECS to RDS
resource "aws_security_group" "hasura_rds" {
  name       = "${var.rds_db_name}-sg"
  description = "allow inbound access from the hasura tasks only"
  vpc_id      = var.vpc_id

  ingress {
    protocol        = "tcp"
    from_port       = "5432"
    to_port         = "5432"
    security_groups = concat([aws_security_group.hasura_ecs.id], var.additional_db_security_groups)
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ec2 to rds
resource "aws_security_group" "allow_internal_postgres_in" {
  name        = "allow_internal_postgres_in-${var.rds_db_name}"
  description = "Allows internal postgres in"
  vpc_id      = var.vpc_id
}

resource "aws_security_group_rule" "network_ingress_postgres_only" {
  security_group_id = "${aws_security_group.allow_internal_postgres_in.id}"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  type              = "ingress"
  cidr_blocks       = [
                        "172.17.0.0/16"
                       ]
}

resource "aws_security_group_rule" "allow_postgres_http_out" {
  security_group_id = "${aws_security_group.allow_internal_postgres_in.id}"
  from_port         = 0
  to_port           = 0
  protocol          = "All"
  type              = "egress"
  cidr_blocks       = ["0.0.0.0/0"]
}

# -----------------------------------------------------------------------------
# Create RDS
# -----------------------------------------------------------------------------

resource "aws_db_subnet_group" "hasura" {
  name       = "${var.rds_db_name}-subnet-group"
  subnet_ids = var.private_subnet_ids
}

resource "aws_db_instance" "hasura" {
  db_name                = var.rds_db_name
  identifier             = var.rds_db_name
  username               = var.rds_username
  password               = var.rds_password
  port                   = "5432"
  engine                 = "postgres"
  engine_version         = var.rds_engine_version
  instance_class         = var.rds_instance
  allocated_storage      = "10"
  storage_encrypted      = var.rds_storage_encrypted
  vpc_security_group_ids = [aws_security_group.hasura_rds.id, aws_security_group.allow_internal_postgres_in.id]
  db_subnet_group_name   = aws_db_subnet_group.hasura.name
  parameter_group_name   = var.rds_param_group
  multi_az               = var.multi_az
  storage_type           = "gp2"
  publicly_accessible    = true

  allow_major_version_upgrade = false
  auto_minor_version_upgrade  = false
  apply_immediately           = true
  maintenance_window          = "sun:02:00-sun:04:00"
  skip_final_snapshot         = true
  copy_tags_to_snapshot       = true
  backup_retention_period     = 7
  backup_window               = "04:00-06:00"

  lifecycle {
    prevent_destroy = false
  }
}

# -----------------------------------------------------------------------------
# Create logging
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "hasura" {
  name = "/ecs/hasura-${var.rds_db_name}"
  retention_in_days = 5
}


# -----------------------------------------------------------------------------
# Create a task definition
# -----------------------------------------------------------------------------

locals {
  ecs_environment = [
    {
      name  = "HASURA_GRAPHQL_ADMIN_SECRET",
      value = "${var.hasura_admin_secret}"
    },
    {
      name  = "HASURA_GRAPHQL_DATABASE_URL",
      value = "postgres://${var.rds_username}:${var.rds_password}@${aws_db_instance.hasura.endpoint}/${var.rds_db_name}"
    },
    {
      name  = "HASURA_GRAPHQL_ENABLE_CONSOLE",
      value = "${var.hasura_console_enabled}"
    },
    {
      name  = "HASURA_GRAPHQL_CORS_DOMAIN",
      value = "https://${var.app_domain}:443, https://${var.app_domain}"
    },
    {
      name  = "HASURA_GRAPHQL_PG_CONNECTIONS",
      value = "100"
    },
    {
      name  = "HASURA_GRAPHQL_JWT_SECRET",
      value = "{\"type\":\"${var.hasura_jwt_secret_algo}\", \"key\": \"${var.hasura_jwt_secret_key}\"}"
    }
  ]

  ecs_container_definitions = [
    {
      image       = "hasura/graphql-engine:${var.hasura_version_tag}",
      cpu       = 40,
      memory    = 1024,
      essential   = true,
      mountPoints = [],
      volumesFrom = [],
      name        = "hasura",
      networkMode = "awsvpc",

      portMappings = [
        {
          protocol      = "tcp",
          containerPort = 8080,
          hostPort      = 8080
        }
      ]

      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-group         = "${aws_cloudwatch_log_group.hasura.name}",
          awslogs-region        = "${var.region}",
          awslogs-stream-prefix = "ecs"
        }
      }

      environment = flatten([local.ecs_environment, var.environment])
    }
  ]
}

resource "aws_ecs_task_definition" "hasura" {
  family                   = "hasura-${var.rds_db_name}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "1024"
  execution_role_arn       = "arn:aws:iam::533085732793:role/system/hasura-role"
  tags                     = { "name": "hasura-${var.rds_db_name}" }
  container_definitions = jsonencode(local.ecs_container_definitions)
}

resource "aws_appautoscaling_target" "this" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${aws_ecs_cluster.hasura.name}/${aws_ecs_service.hasura.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  depends_on = [aws_ecs_service.hasura]
}

resource "aws_appautoscaling_policy" "this" {
  name               = "${var.rds_db_name}-autoscaling-policy"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.this.resource_id
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  service_namespace  = aws_appautoscaling_target.this.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 65
    scale_in_cooldown  = 300
    scale_out_cooldown = 300

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }

  depends_on = [aws_appautoscaling_target.this]
}

# -----------------------------------------------------------------------------
# Create ECS cluster
# -----------------------------------------------------------------------------

resource "aws_ecs_cluster" "hasura" {
  name = var.ecs_cluster_name
}


# -----------------------------------------------------------------------------
# Create the ECS service
# -----------------------------------------------------------------------------

resource "aws_ecs_service" "hasura" {
  depends_on = [
    aws_ecs_task_definition.hasura,
    aws_alb_listener.hasura,
  ]

  name            = "${var.rds_db_name}-service"
  cluster         = aws_ecs_cluster.hasura.id
  tags            = {}
  task_definition = aws_ecs_task_definition.hasura.arn
  desired_count   = var.multi_az == true ? "2" : "1"
  launch_type     = "FARGATE"

  network_configuration {
    assign_public_ip = true
    security_groups  = [aws_security_group.hasura_ecs.id]
    subnets          = var.public_subnet_ids
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.hasura.id
    container_name   = "hasura"
    container_port   = "8080"
  }
}

# -----------------------------------------------------------------------------
# Create the ALB log bucket
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "hasura" {
  bucket        = "hasura-${var.region}-${var.hasura_subdomain}-${var.domain}"
  force_destroy = "true"
}

resource "aws_s3_bucket_acl" "hasura-acl" {
  bucket = aws_s3_bucket.hasura.id
  acl    = "private"
}

# -----------------------------------------------------------------------------
# Add IAM policy to allow the ALB to log to it
# -----------------------------------------------------------------------------

data "aws_elb_service_account" "main" {
}

data "aws_iam_policy_document" "hasura" {
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.hasura.arn}/alb/*"]

    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.main.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "hasura" {
  bucket = aws_s3_bucket.hasura.id
  policy = data.aws_iam_policy_document.hasura.json
}

# -----------------------------------------------------------------------------
# Create the ALB
# -----------------------------------------------------------------------------

resource "aws_alb" "hasura" {
  name            = "${var.rds_db_name}-alb"
  subnets         = var.public_subnet_ids
  security_groups = [aws_security_group.hasura_alb.id]

  access_logs {
    bucket  = aws_s3_bucket.hasura.id
    prefix  = "alb"
    enabled = true
  }
}

# -----------------------------------------------------------------------------
# Create the ALB target group for ECS
# -----------------------------------------------------------------------------

resource "aws_alb_target_group" "hasura" {
  name        = "${var.rds_db_name}-alb"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path    = "/healthz"
    matcher = "200"
  }
}

# -----------------------------------------------------------------------------
# Create the ALB listener
# -----------------------------------------------------------------------------

resource "aws_alb_listener" "hasura" {
  load_balancer_arn = aws_alb.hasura.id
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.hasura.arn

  default_action {
    target_group_arn = aws_alb_target_group.hasura.id
    type             = "forward"
  }
}

# -----------------------------------------------------------------------------
# Create Route 53 record to point to the ALB
# -----------------------------------------------------------------------------

resource "aws_route53_record" "hasura" {
  zone_id = data.aws_route53_zone.hasura.zone_id
  name    = "${var.hasura_subdomain}.${var.domain}"
  type    = "A"

  alias {
    name                   = aws_alb.hasura.dns_name
    zone_id                = aws_alb.hasura.zone_id
    evaluate_target_health = true
  }
}

# -----------------------------------------------------------------------------
# RDS Alerts
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "low_memory" {
  alarm_name          = "db-${var.rds_db_name}-low-memory"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "3"
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = "600"
  statistic           = "Maximum"
  threshold           = "100"
  alarm_description   = "Database instance memory above threshold"
  alarm_actions       = var.alarm_sns_topics
  ok_actions          = var.alarm_sns_topics

  dimensions = {
    DBInstanceIdentifier = var.rds_db_name
  }
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "db-${var.rds_db_name}-high-cpu"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "3"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "600"
  statistic           = "Maximum"
  threshold           = "80"
  alarm_description   = "Database instance CPU above threshold"
  alarm_actions       = var.alarm_sns_topics
  ok_actions          = var.alarm_sns_topics

  dimensions = {
    DBInstanceIdentifier = var.rds_db_name
  }
}

resource "aws_cloudwatch_metric_alarm" "low_disk" {
  alarm_name          = "db-${var.rds_db_name}-low-disk"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "3"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "600"
  statistic           = "Maximum"
  threshold           = "1000000000"
  unit                = "Bytes"
  alarm_description   = "Database instance disk space is low"
  alarm_actions       = var.alarm_sns_topics
  ok_actions          = var.alarm_sns_topics

  dimensions = {
    DBInstanceIdentifier = var.rds_db_name
  }
}

resource "aws_cloudwatch_metric_alarm" "low_cpu_credits" {
  count = substr(var.rds_instance, 0, 4) == "db.t" ? 1 : 0

  alarm_name          = "db-${var.rds_db_name}-low-cpu-credits"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "3"
  metric_name         = "CPUCreditBalance"
  namespace           = "AWS/RDS"
  period              = "600"
  statistic           = "Maximum"
  threshold           = "100"
  alarm_description   = "Database instance CPU credit balance is low"
  alarm_actions       = var.alarm_sns_topics
  ok_actions          = var.alarm_sns_topics

  dimensions = {
    DBInstanceIdentifier = var.rds_db_name
  }
}
