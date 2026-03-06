# terraform/ec2.tf
# Data source for latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"] # Amazon Linux 2023
  }
}

# Launch Template – defines EC2 instance config
resource "aws_launch_template" "app" {
  name_prefix   = "securebankapp-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.medium"

  # IAM role for SSM + ECR access
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  # Encrypted root volume (AWS-managed key)
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 32
      volume_type = "gp3"
      encrypted   = true
    }
  }

  # Private subnet – no public IP
  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.app.id]
  }

  # User Data – joins ECS cluster + installs Docker only
  # NO manual docker run – ECS service handles container
  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -x
    exec > /var/log/user-data.log 2>&1

    echo "User data STARTED at $(date)"

    # Update system
    yum update -y

    # Install Docker
    amazon-linux-extras install docker -y || yum install docker -y
    systemctl enable docker
    systemctl start docker
    sleep 10  # Give Docker time to start
    docker info || echo "ERROR: Docker failed to start"

    # Join ECS cluster
    echo ECS_CLUSTER=securebankapp-cluster >> /etc/ecs/ecs.config

    # Install AWS CLI (for debugging if needed)
    yum install -y aws-cli

    # SSM Agent (already installed on AL2023, but ensure running)
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent

    echo "User data FINISHED at $(date)"
    echo "Docker status:"
    systemctl status docker
    echo "ECS config:"
    cat /etc/ecs/ecs.config
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "securebankapp-app"
    }
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "app" {
  name                = "securebankapp-asg"
  min_size            = 2
  max_size            = 6
  desired_capacity    = 2
  vpc_zone_identifier = [for s in aws_subnet.private : s.id]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.app.arn]

  # Health check settings – give plenty of time for ECS + container startup
  health_check_type           = "ELB"
  health_check_grace_period   = 900   # 15 minutes – crucial for ECS boot
  wait_for_capacity_timeout   = "30m" # Allow up to 30 min for healthy instances

  # Rolling refresh for safer updates
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "securebankapp-app"
    propagate_at_launch = true
  }
}

# Scale-out policy (CPU-based)
resource "aws_autoscaling_policy" "scale_out" {
  name                   = "securebankapp-scale-out"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

# ECR Repository
resource "aws_ecr_repository" "app" {
  name                 = "securebankapp"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "securebankapp-app"
    Project     = "SecureBankApp"
    Environment = var.environment
  }
}