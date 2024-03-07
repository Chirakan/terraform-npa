##################################################################################
# PROVIDERS
##################################################################################

provider "aws" {
  access_key = "ASIA2UC3AGU4KZM2GL5D"
  secret_key = "am5IiDxQeThOjModIkvzOVpTXw09/8QHtQHKpZUE"
  token      = "FwoGZXIvYXdzEOr//////////wEaDHqH+SWMarF5Xx1FISLFAa1DxJxm6REn1iUUqDvrxdMfJKu15UOFFmbxnhMLIYHE03tq7ZuBgIWL2OdBmXmr+XGrzkkUXiHSIIytzn1pYUVFs8mEhFtzkAuo5QU7cJvKoFVMOx+ecsQE0aRkBa5ZUWO5m51g+gq9B4vJ36qa93kd2U6ePXce3iiWwNDA3fHGkpbLVIS1pvPglIe9m9rVwiC6thVGU6P3NwMdGh7NfbjVLYrsefA8jh3OW/hCX2LcoAJNDL/YhI6QEJrObsIuxnHhePdcKMPy8q4GMi1BhWzo4uyO57SX0KB0uKH/NXW3m1tieoxHEUycxvcsw0VyS2QV+rAVOHG/RVA="
  region     = "us-east-1"
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
  tags = {
    Name = "testVPC"
  }
}

resource "aws_subnet" "dtestvpc_subnet" {
  vpc_id = aws_vpc.testvpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1b"
  tags = {
    Name = "Public1"
  }
}

resource "aws_security_group" "sg1" {
  name        = "AllowSSHandWeb"
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

resource "aws_instance" "testweb" {
  ami                    = data.aws_ami.aws-linux.id
  instance_type          = "t2.micro"
  key_name               = "vockey"
  vpc_security_group_ids = [aws_security_group.sg1.id]
  subnet_id = aws_subnet.dtestvpc_subnet.id #Deploy in Public 1
  root_block_device {
    volume_size = 8
    volume_type = "gp2"
  }
  tags = {
    Name = "tfTest"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.testvpc.id
  tags = {
    Name = "public_gw"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.testvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.dtestvpc_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

##################################################################################
# OUTPUT
##################################################################################

output "aws_instance_public_dns" {
  value = aws_instance.testweb.public_dns
}

