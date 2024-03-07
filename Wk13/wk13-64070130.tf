##################################################################################
# VARIABLE
##################################################################################
#call -> terraform plan -var-file values.tfvars
variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "aws_session_token" {}
variable "default_region" {}
variable "key_name" {}
variable "default_name" {
  default     = "itkmitl"
}

##################################################################################
# LOCALS
##################################################################################

locals {
  default_tags = {
    itclass = "npa24"
    itgroup = "year3"
  }
}

##################################################################################
# PROVIDERS
##################################################################################

provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  token      = var.aws_session_token
  region     = var.default_region
}

##################################################################################
# DATA
##################################################################################

data "aws_ami" "aws-linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

##################################################################################
# RESOURCES
##################################################################################

#This uses the default VPC.  It WILL NOT delete it on destroy.
resource "aws_vpc" "testvpc" {
  cidr_block = "10.0.0.0/16"
  tags = merge(local.default_tags,{
    Name = "${var.default_name}-VPC"
  })
}

resource "aws_subnet" "dtestvpc_subnet1" {
  vpc_id = aws_vpc.testvpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1b"
  tags = merge(local.default_tags,{
    Name = "${var.default_name}-Public-subnet1"
  })
}

resource "aws_subnet" "dtestvpc_subnet2" {
  vpc_id = aws_vpc.testvpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1c"
  tags = merge(local.default_tags,{
    Name = "${var.default_name}-Public-subnet2"
  })
}

resource "aws_security_group" "sg1" {
  name        = "itkmitl-AllowSSHandWeb"
  description = "Allow incoming SSH and HTTP traffic to EC2 Instance"
  vpc_id      = aws_vpc.testvpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1 #any
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.testvpc.id
  tags = merge(local.default_tags,{
    Name = "${var.default_name}-gw"
  })
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.testvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.dtestvpc_subnet1.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_subnet_association2" {
  subnet_id      = aws_subnet.dtestvpc_subnet2.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_instance" "testweb1" {
  ami                    = data.aws_ami.aws-linux.id
  instance_type          = "t2.micro"
  key_name               = "vockey"
  vpc_security_group_ids = [aws_security_group.sg1.id]
  subnet_id = aws_subnet.dtestvpc_subnet1.id #Deploy in Public 1
  root_block_device {
    volume_size = 8
    volume_type = "gp2"
  }
  tags = merge(local.default_tags,{
    Name = "${var.default_name}-server1"
  })
}

resource "aws_instance" "testweb2" {
  ami                    = data.aws_ami.aws-linux.id
  instance_type          = "t2.micro"
  key_name               = "vockey"
  vpc_security_group_ids = [aws_security_group.sg1.id]
  subnet_id = aws_subnet.dtestvpc_subnet2.id #Deploy in Public 2
  root_block_device {
    volume_size = 8
    volume_type = "gp2"
  }
  tags = merge(local.default_tags,{
    Name = "${var.default_name}-server2"
  })
}

resource "aws_lb" "elb-webLB" {
  name               = "itkmitl-elb-webLB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.sg1.id]
  subnets            = [aws_subnet.dtestvpc_subnet1.id, aws_subnet.dtestvpc_subnet2.id]
  enable_deletion_protection = false
  tags = merge(local.default_tags,{
    Name = "${var.default_name}-elb-webLB"
  })
}

resource "aws_lb_target_group" "lb-tg" {
  name     = "itkmitl-targetgroup"
  target_type = "instance"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.testvpc.id
  health_check {
    path                = "/"
    protocol            = "HTTP"
    port                = "80"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
  }
  target_health_state {
    enable_unhealthy_connection_termination = false
  }
  tags = merge(local.default_tags,{
    Name = "${var.default_name}-tg"
  })
}

resource "aws_lb_target_group_attachment" "lb-attachment1" {
  target_group_arn = aws_lb_target_group.lb-tg.arn
  target_id        = aws_instance.testweb1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "lb-attachment2" {
  target_group_arn = aws_lb_target_group.lb-tg.arn
  target_id        = aws_instance.testweb2.id
  port             = 80
}

# Listener rule for HTTP traffic on each of the ALBs
resource "aws_lb_listener" "lb_listener_http" {
  load_balancer_arn    = aws_lb.elb-webLB.arn
  port                 = "80"
  protocol             = "HTTP"
  default_action {
    target_group_arn = aws_lb_target_group.lb-tg.arn
    type             = "forward"
  }
  tags = merge(local.default_tags,{
    Name = "${var.default_name}-lb_listener_http"
  })
}

##################################################################################
# OUTPUT
##################################################################################

# output "aws_instance_public_dns" {
#   value = aws_instance.testweb1.public_dns
# }


