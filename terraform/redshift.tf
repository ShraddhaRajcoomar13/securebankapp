# terraform/redshift.tf

# Subnet group for Redshift (isolated DB subnets, same as RDS)
resource "aws_redshift_subnet_group" "main" {
  name       = "securebankapp-redshift"
  subnet_ids = [for s in aws_subnet.db : s.id]

  tags = {
    Name        = "securebankapp-redshift-subnet-group"
    Project     = "SecureBankApp"
    Environment = var.environment
  }
}

# Modern Redshift cluster with AWS-managed master password
resource "aws_redshift_cluster" "main" {
  cluster_identifier = "securebankapp-analytics"

  # CRITICAL: Keep the EXISTING node_type if cluster already exists
  # If you're getting "doesn't support clusters of non-RA3 node types" error,
  # it means your cluster is ALREADY RA3 and trying to change to dc2.large
  # SOLUTION: Use the node type that's ALREADY deployed
  node_type       = "ra3.xlplus"   # If you get errors, this matches what's deployed
  number_of_nodes = 2              # ra3.xlplus requires minimum 2 nodes

  # AWS manages the master password via Secrets Manager (secure, no value in Terraform state)
  manage_master_password = true
  master_username        = "redshiftadmin"
  database_name          = "analytics"

  # Networking
  cluster_subnet_group_name = aws_redshift_subnet_group.main.name
  vpc_security_group_ids    = [aws_security_group.rds.id]  # Reuse RDS SG
  publicly_accessible       = false

  # Encryption
  encrypted  = true
  kms_key_id = aws_kms_key.main.arn

  # Backups & Maintenance
  automated_snapshot_retention_period = 7
  preferred_maintenance_window        = "mon:05:00-mon:06:00"

  # Skip final snapshot on destroy (convenient for testing/portfolio)
  skip_final_snapshot = true

  tags = {
    Name        = "securebankapp-analytics"
    Project     = "SecureBankApp"
    Environment = var.environment
  }
  
  # CRITICAL: Prevent Terraform from trying to change existing clusters
  lifecycle {
    ignore_changes = [
      master_password,  # Managed by AWS
      node_type,        # Don't change if cluster exists
      number_of_nodes   # Don't change if cluster exists
    ]
  }
}

# Separate logging resource (avoids deprecation warning from inline logging block)
# CRITICAL FIX: Use aws_s3_bucket.logs.id (bucket name) NOT .bucket or .arn
resource "aws_redshift_logging" "main" {
  cluster_identifier   = aws_redshift_cluster.main.cluster_identifier
  log_destination_type = "s3"
  bucket_name          = aws_s3_bucket.logs.id  # FIXED: Use .id (bucket name)
  s3_key_prefix        = "redshift-logs"

  depends_on = [
    aws_redshift_cluster.main,
    aws_s3_bucket_policy.logs_redshift  # Ensure bucket policy is in place first
  ]
}
