# terraform/rds.tf

# Subnet group for RDS (private subnets only)
resource "aws_db_subnet_group" "main" {
  name       = "securebankapp-db-subnet"
  subnet_ids = [for s in aws_subnet.db : s.id]

  tags = {
    Name        = "securebankapp-db-subnet"
    Project     = "SecureBankApp"
    Environment = var.environment
  }
}

# Parameter group for Postgres 16 – with security & audit logging
resource "aws_db_parameter_group" "postgres" {
  name        = "securebankapp-pg16"
  family      = "postgres16"
  description = "SecureBankApp Postgres 16 parameter group"

  # Dynamic parameters (apply immediately)
  parameter {
    name  = "log_connections"
    value = "1"
  }
  parameter {
    name  = "log_disconnections"
    value = "1"
  }
  parameter {
    name  = "log_statement"
    value = "ddl"  # Log all DDL — good for audit
  }

  # Static parameters (require reboot) — mark explicitly
  parameter {
    name         = "log_min_duration_statement"
    value        = "250"   # Log queries >250ms — helps spot slow queries
    apply_method = "pending-reboot"
  }
  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"  # Enables query stats (very useful)
    apply_method = "pending-reboot"
  }

  tags = {
    Name        = "securebankapp-pg16"
    Project     = "SecureBankApp"
    Environment = var.environment
  }
}

# RDS DB Instance – PostgreSQL 16 (single instance, Multi-AZ for HA)
resource "aws_db_instance" "main" {
  identifier = "securebankapp-postgres"

  # Engine & version
  engine         = "postgres"
  engine_version = "16"

  # Instance & storage
  instance_class        = "db.t3.medium"
  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.main.arn

  # Credentials (securely from Secrets Manager)
  db_name   = "bankdb"
  username  = "bankadmin"
  password  = jsondecode(aws_secretsmanager_secret_version.db_password.secret_string)["password"]

  # Networking – private only
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false  # Critical security setting

  # High availability & backups
  multi_az               = true
  backup_retention_period = 7
  backup_window          = "03:00-04:00"  # UTC
  maintenance_window     = "Mon:04:00-Mon:05:00"
  deletion_protection    = false
  skip_final_snapshot    = true
  final_snapshot_identifier = "securebankapp-final"

  # Monitoring & logging
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.rds_monitoring.arn
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Performance Insights (highly recommended for production)
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.main.arn
  performance_insights_retention_period = 7

  # Parameter group – uncomment when ready (after manual detach or reboot)
  parameter_group_name = aws_db_parameter_group.postgres.name

  tags = {
    Name        = "securebankapp-postgres"
    Project     = "SecureBankApp"
    Environment = var.environment
  }

  # Optional: allow major version upgrades in future
  allow_major_version_upgrade = false
  auto_minor_version_upgrade  = true
}