# terraform/ecs.tf

resource "aws_ecs_cluster" "main" {
  name = "securebankapp-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = {
    Name        = "securebankapp-cluster"
    Project     = "SecureBankApp"
    Environment = var.environment
  }
}

resource "aws_ecs_task_definition" "app" {
  family                   = "securebankapp-task"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  cpu                      = "512"
  memory                   = "1024"

  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "bankapp"
      image     = "608283508247.dkr.ecr.us-east-1.amazonaws.com/securebankapp:latest"
      essential = true

      portMappings = [
        {
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
        }
      ]

      # Environment variables the app needs at runtime.
      # Secrets (DB password, JWT) are fetched from Secrets Manager by the app itself via IAM role.
      environment = [
        { name = "DB_HOST",            value = aws_db_instance.main.address },
        { name = "DB_NAME",            value = "bankdb" },
        { name = "AWS_REGION",         value = "us-east-1" },
        { name = "JWT_EXPIRE_MINUTES", value = "30" },
        { name = "APP_ENV",            value = "production" }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8000/health || exit 1"]
        interval    = 30
        timeout     = 10
        retries     = 3
        startPeriod = 180
      }

      # Log group must match what's defined in monitoring.tf: /securebankapp/app
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/securebankapp/app"
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "bankapp"
        }
      }
    }
  ])

  tags = {
    Name = "securebankapp-task"
  }
}

resource "aws_ecs_service" "app" {
  name                               = "securebankapp-service"
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.app.arn
  desired_count                      = 2
  launch_type                        = "EC2"
  enable_execute_command             = true
  health_check_grace_period_seconds  = 900

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 0   # Keep 0 until first healthy deploy confirmed, then raise to 50

  deployment_controller {
    type = "ECS"
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  ordered_placement_strategy {
    type  = "spread"
    field = "instanceId"
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "bankapp"
    container_port   = 8000
  }

  depends_on = [
    aws_lb.main,
    aws_lb_listener.http,
    aws_lb_target_group.app
  ]

  tags = {
    Name = "securebankapp-service"
  }
}
