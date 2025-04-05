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

resource "aws_instance" "web" {
  count           = 2
  ami             = "ami-04e914639d0cca79a"
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
