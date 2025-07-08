provider "aws" {
  region = "eu-north-1"

}

variable "vpc_id" {
  description = "The ID of the VPC to query for subnets"
  type        = string
  default     = "vpc-0edba5c7e0c329ce5"

}

# Data source to fetch subnets in the specified VPC
data "aws_subnets" "custom_vpc" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

# LoadBalancer security group
resource "aws_security_group" "lb_sg" {
  name        = "lb_sg"
  description = "Allow TCP traffic on port 80"
  vpc_id      = var.vpc_id
  tags = {
    Name = "LoadBalancerSecurityGroup"
  }
}

# Allow inbound HTTP traffic on port 80 from anywhere
resource "aws_vpc_security_group_ingress_rule" "allow_http_lb" {
  security_group_id = aws_security_group.lb_sg.id
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0" # Allow HTTP from anywhere
}

# Allow outbound traffic on all ports
resource "aws_vpc_security_group_egress_rule" "outbound_lb" {
  security_group_id = aws_security_group.lb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

# security group for EC2
resource "aws_security_group" "ec2_sg" {
  name        = "ec2_sg"
  description = "Allow TCP traffic on port 22 and 80"
  vpc_id      = var.vpc_id
  tags = {
    Name = "Ec2SecurityGroup"
  }
}

# Allow inbound SSH traffic on port 22 from anywhere 
resource "aws_vpc_security_group_ingress_rule" "allow_ssh" {
  security_group_id = aws_security_group.ec2_sg.id
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0" # Allow SSH from anywhere (not recommended for production)
}

# Allow HTTP traffic on port 80 from anywhere
resource "aws_vpc_security_group_ingress_rule" "allow_http" {
  security_group_id            = aws_security_group.ec2_sg.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.lb_sg.id
}

# Allow outbound traffic on all ports
resource "aws_vpc_security_group_egress_rule" "outbound_ec2" {
  security_group_id = aws_security_group.ec2_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}


# security group for mysql RDS
resource "aws_security_group" "db_sg" {
  name        = "db_sg"
  description = "Allow TCP traffic on port 3306"
  vpc_id      = var.vpc_id

  tags = {
    Name = "DbSecurityGroup"
  }
}

# Allow inbound MySQL traffic on port 3306 from the EC2 security group
# This allows the EC2 instances to connect to the RDS instance
resource "aws_vpc_security_group_ingress_rule" "db_ingress" {
  security_group_id            = aws_security_group.db_sg.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.ec2_sg.id
}

# Allow outbound traffic on all ports from the RDS security group
resource "aws_vpc_security_group_egress_rule" "db_egress" {
  security_group_id = aws_security_group.db_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

# Subnet group for RDS
resource "aws_db_subnet_group" "subnet_group" {
  name = "db_subnet_group"
  subnet_ids = [
    data.aws_subnets.custom_vpc.ids[0],
    data.aws_subnets.custom_vpc.ids[1]
  ]

  tags = {
    Name = "My DB subnet group"
  }
}

# Create an RDS MySQL instance
resource "aws_db_instance" "mysql_instance" {
  identifier             = "db-instance"
  allocated_storage      = 10
  db_name                = "app_db"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  username               = "admin"
  password               = "password123"
  parameter_group_name   = "default.mysql8.0"
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.subnet_group.name
  tags = {
    Name = "MyRDSInstance"
  }
}


# Archive a single file.
data "archive_file" "archive" {
  type        = "zip"
  source_dir  = "${path.module}/app/"
  output_path = "${path.module}/zip_output/app_code.zip"
}

# Create s3 bucket to store the application version
resource "aws_s3_bucket" "app_bucket" {
  bucket = "calenderapp.bucket"
  tags = {
    Name = "CalenderAppBucket"
  }
}

# Set the ownership controls for the S3 bucket
resource "aws_s3_bucket_ownership_controls" "owner" {
  bucket = aws_s3_bucket.app_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}


# Set the ACL for the S3 bucket to private
# This ensures that the bucket is private and only the owner can access it
resource "aws_s3_bucket_acl" "bucket_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.owner]
  bucket     = aws_s3_bucket.app_bucket.id
  acl        = "private"
}

# Enable versioning for the S3 bucket
resource "aws_s3_bucket_versioning" "bucket_versioning" {
  bucket = aws_s3_bucket.app_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}


# Upload the application version to S3
resource "aws_s3_object" "app_object" {
  bucket = aws_s3_bucket.app_bucket.id
  key    = "beanstalk/app_code_${timestamp()}.zip"
  source = data.archive_file.archive.output_path
}

# Create an IAM role for Elastic Beanstalk service
resource "aws_iam_role" "beanstalk_service" {
  name = "beanstalk_service_role"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "elasticbeanstalk.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name = "BeanstalkServiceRole"
  }
}


# Attach the AWS managed policy for Elastic Beanstalk service to the role
resource "aws_iam_role_policy_attachment" "beanstalk_policy1" {
  role       = aws_iam_role.beanstalk_service.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth"

}

# Attach the AWS managed policy for Elastic Beanstalk managed updates to the role
resource "aws_iam_role_policy_attachment" "beanstalk_policy2" {
  role       = aws_iam_role.beanstalk_service.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkManagedUpdatesCustomerRolePolicy"
}

# Create an IAM role for the Elastic Beanstalk environment
resource "aws_iam_role" "beanstalk_ec2_role" {
  name = "beanstalk_ec2_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
  tags = {
    Name = "BeanstalkEC2_EnvironmentRole"
  }
}

# Attach the AWS managed policy for Elastic Beanstalk EC2 instances to the role
resource "aws_iam_role_policy_attachment" "beanstalk_ec2_policy1" {
  role       = aws_iam_role.beanstalk_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
}

# Create an IAM instance profile for the Elastic Beanstalk environment
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "beanstalk_ec2_instance_profile"
  role = aws_iam_role.beanstalk_ec2_role.name
}


# Create an ElasticBeanStalks application
resource "aws_elastic_beanstalk_application" "app" {
  name        = "CalenderApp"
  description = "Elastic Beanstalk application for the Calender App"
  tags = {
    Name = "CalenderApp"
  }

  appversion_lifecycle {
    service_role          = aws_iam_role.beanstalk_service.arn
    max_count             = 3
    delete_source_from_s3 = true
  }
}

# Create an Elastic Beanstalk application version
resource "aws_elastic_beanstalk_application_version" "app_version" {
  name        = replace(aws_s3_object.app_object.key, "beanstalk/", "")
  application = aws_elastic_beanstalk_application.app.name
  description = "application version created by terraform"
  bucket      = aws_s3_bucket.app_bucket.id
  key         = aws_s3_object.app_object.key

  tags = {
    s3_key = aws_s3_object.app_object.key
  }

}


# Beanstalk Environment
resource "aws_elastic_beanstalk_environment" "app_env" {
  name                = "CalenderAppEnv"
  application         = aws_elastic_beanstalk_application.app.name
  version_label       = aws_elastic_beanstalk_application_version.app_version.name
  solution_stack_name = "64bit Amazon Linux 2023 v4.7.0 running PHP 8.4"

  setting {
    namespace = "aws:ec2:vpc"
    name      = "VPCId"
    value     = var.vpc_id
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = join(",", data.aws_subnets.custom_vpc.ids)
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "ELBSubnets"
    value     = join(",", data.aws_subnets.custom_vpc.ids)
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_HOSTNAME"
    value     = aws_db_instance.mysql_instance.address
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_PORT"
    value     = "3306"
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_DB_NAME"
    value     = aws_db_instance.mysql_instance.db_name
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_USERNAME"
    value     = aws_db_instance.mysql_instance.username
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_PASSWORD"
    value     = aws_db_instance.mysql_instance.password
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "ServiceRole"
    value     = aws_iam_role.beanstalk_service.arn
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment:process:default"
    name      = "HealthCheckPath"
    value     = "/"
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.ec2_profile.name
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "DisableDefaultEC2SecurityGroup"
    value     = "true"
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "SecurityGroups"
    value     = aws_security_group.ec2_sg.id
  }

  setting {
    namespace = "aws:elb:loadbalancer"
    name      = "SecurityGroups"
    value     = aws_security_group.lb_sg.id
  }

}


