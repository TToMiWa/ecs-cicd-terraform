provider "aws" {
  region = "eu-north-1"
}

# -----------------------------
# 1. ECS Cluster
# -----------------------------
resource "aws_ecs_cluster" "hello_cluster" {
  name = "hello-ecs-cluster"
}

# -----------------------------
# 2. IAM Role + Instance Profile for ECS
# -----------------------------
resource "aws_iam_role" "ecs_instance_role" {
  name = "ecsInstanceRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_instance_policy" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "ecsInstanceProfile"
  role = aws_iam_role.ecs_instance_role.name
}

# -----------------------------
# 3. Security Group
# -----------------------------
resource "aws_security_group" "ecs_sg" {
  name        = "hello-ecs-sg"
  description = "Allow HTTP (3000) and SSH"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
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

# -----------------------------
# 4. Data sources for subnets/VPC
# -----------------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# -----------------------------
# 5. Launch Template
# -----------------------------
resource "aws_launch_template" "ecs_launch_template" {
  name_prefix   = "hello-ecs-template-"
  image_id      = "ami-039a3ca32e09e90fd" # ECS-optimized AMI
  instance_type = "t3.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }

  vpc_security_group_ids = [aws_security_group.ecs_sg.id]

  user_data = base64encode(<<EOF
#!/bin/bash
echo ECS_CLUSTER=${aws_ecs_cluster.hello_cluster.name} >> /etc/ecs/ecs.config
systemctl restart ecs
EOF
)

}

# -----------------------------
# 6. Auto Scaling Group
# -----------------------------
resource "aws_autoscaling_group" "ecs_asg" {
  name               = "hello-ecs-asg"
  max_size           = 2
  min_size           = 1
  desired_capacity   = 1
  vpc_zone_identifier = data.aws_subnets.default.ids
  health_check_type  = "EC2"

  launch_template {
    id      = aws_launch_template.ecs_launch_template.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "hello-ecs-instance"
    propagate_at_launch = true
  }
}

# -----------------------------
# 7. ECS Task Definition
# -----------------------------
resource "aws_ecs_task_definition" "app_task" {
  family                   = "hello-terraform-task"
  network_mode              = "bridge"
  requires_compatibilities  = ["EC2"]
  cpu                       = "256"
  memory                    = "512"

  container_definitions = jsonencode([
    {
      name      = "hello-app"
      image     = "404119728613.dkr.ecr.eu-north-1.amazonaws.com/hello-terraform:latest"
      essential = true
      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
        }
      ]
    }
  ])
}

# -----------------------------
# 8. ECS Service (Public App)
# -----------------------------
resource "aws_ecs_service" "app_service" {
  name            = "hello-app-service"
  cluster         = aws_ecs_cluster.hello_cluster.id
  task_definition = aws_ecs_task_definition.app_task.arn
  desired_count   = 1
  launch_type     = "EC2"

  depends_on = [
    aws_autoscaling_group.ecs_asg
  ]
}
