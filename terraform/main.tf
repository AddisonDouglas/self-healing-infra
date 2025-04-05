#Terraform block to define the required providers and their versions
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

## Configure the AWS Provider, gets deault values from when you do aws configure
## or you can set the region and access keys here
provider "aws" {
}

#aws_key_pair registers a public key with AWS, allowing you to connect to the instance using SSH
resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

#allows access to the list of AWS Availability Zones(physically isolated data centers)
data "aws_availability_zones" "available" {}

#Provides a VPC resource, VPC(Virtual Private Cloud), resembles a traditional network that you'd operate in your own data center
resource "aws_vpc" "vpc_main" {
}
#allows communication between your VPC and the internet
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc_main.id
}

variable "subnet_cidr" {
  description = "List of CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

resource "aws_subnet" "subnet_main" {
  count                   = 2
  vpc_id                  = aws_vpc.vpc_main.id
  cidr_block              = var.subnet_cidr[count.index]
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true
}

resource "aws_security_group" "web_sg" {
  name_prefix = "web-sg-"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
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

resource "aws_security_group" "public_alb" {
  name        = "public_alb"
  description = "Allow public traffic for Application Load Balancer."
  vpc_id      = aws_vpc.vpc_main.id

  # for allowing health check traffic
  ingress {
    from_port = 32768 # ephemeral port range: https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_PortMapping.html
    # to_port     = 61000
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] // anywhere
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] // anywhere
  }

  ingress {
    # TLS (change to whatever ports you need)
    from_port = 443
    to_port   = 443
    protocol  = "tcp"

    # Please restrict your ingress to only necessary IPs and ports.
    # Opening to 0.0.0.0/0 can lead to security vulnerabilities.
    cidr_blocks = ["0.0.0.0/0"] # add a CIDR block here
  }

  ingress {
    description = "Bastion"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] // anywhere
    self        = false
  }

  # allow all traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "web" {
  count           = 2
  ami             = "ami-020fbc00dbecba358" # Amazon Linux AMI
  instance_type   = "t2.micro"
  key_name        = aws_key_pair.deployer.key_name
  security_groups = [aws_security_group.web_sg.name]

  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install -y nginx
              echo "<h1>Welcome to Web Server ${count.index + 1}</h1>" > /usr/share/nginx/html/index.html
              systemctl enable nginx
              systemctl start nginx
              EOF

  tags = {
    Name = "WebServer-${count.index + 1}"
  }
}

output "public_ips" {
  value = [for instance in aws_instance.web : instance.public_ip]
}

resource "aws_lb" "test" {
  name               = "test-lb-tf"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.public_alb.id]
  subnets            = [for subnet in aws_subnet.subnet_main : subnet.id]


}

