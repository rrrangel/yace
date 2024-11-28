provider "aws" {
  region = var.aws_region
}

# VPC Configuration
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.app_name}-vpc"
  }
}

resource "aws_subnet" "public_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "${var.app_name}-public-1"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "${var.app_name}-public-2"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.app_name}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.app_name}-public-rt"
  }
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# Security Group
resource "aws_security_group" "yace" {
  name        = "${var.app_name}-sg"
  description = "Security group for YACE exporter"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 5000    # Changed to explicitly use 5000 instead of var.container_port
    to_port     = 5000    # Changed to explicitly use 5000 instead of var.container_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.app_name}-cluster"
}

# Task Definition
resource "aws_ecs_task_definition" "yace" {
  family                   = var.app_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn           = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = var.app_name
      image = "ghcr.io/nerdswords/yet-another-cloudwatch-exporter:${var.yace_version}"
      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
          protocol      = "tcp"
        }
      ]
      environment = []
      mountPoints = [
        {
          sourceVolume  = "config"
          containerPath = "/tmp/config.yml"
          readOnly      = true
        },
        {
          sourceVolume  = "credentials"
          containerPath = "/exporter/.aws/credentials"
          readOnly      = true
        }
      ]
    }
  ])

  volume {
    name = "config"
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.config.id
      root_directory = "/"
    }
  }

  volume {
    name = "credentials"
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.config.id
      root_directory = "/"
    }
  }
}

# ECS Service
resource "aws_ecs_service" "yace" {
  name            = var.app_name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.yace.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public_1.id, aws_subnet.public_2.id]
    security_groups  = [aws_security_group.yace.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.yace.arn
    container_name   = var.app_name
    container_port   = var.container_port
  }
}

# Application Load Balancer
resource "aws_lb" "yace" {
  name               = "${var.app_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.yace.id]
  subnets           = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

resource "aws_lb_target_group" "yace" {
  name        = "${var.app_name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path = "/"
  }
}

resource "aws_lb_listener" "yace" {
  load_balancer_arn = aws_lb.yace.arn
  port              = "5000"    # Changed from 80 to 5000
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.yace.arn
  }
}

# EFS File System for Configuration
resource "aws_efs_file_system" "config" {
  creation_token = "${var.app_name}-config"

  tags = {
    Name = "${var.app_name}-config"
  }
}

resource "aws_efs_mount_target" "config" {
  count           = 2
  file_system_id  = aws_efs_file_system.config.id
  subnet_id       = count.index == 0 ? aws_subnet.public_1.id : aws_subnet.public_2.id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_security_group" "efs" {
  name        = "${var.app_name}-efs-sg"
  description = "Security group for EFS"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.yace.id]
  }
}

# IAM Roles
resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.app_name}-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  name = "${var.app_name}-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "cloudwatch_access" {
  name = "${var.app_name}-cloudwatch-access"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}