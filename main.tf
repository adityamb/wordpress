locals {
  ami_id = "ami-08c40ec9ead489470"
  vpc_id = "vpc-041501c418890ac20"
  ssh_user = "ubuntu"
  key_name = "Demokey"
  private_key_path = "/home/labsuser/wordpress_proj/Demokey.pem"
  prodigw_id= "igw-0f19805ee0671b5ea"
}

provider "aws" {
  region     = "us-east-1"
  access_key = "ASIA4MEG3FAUSQPRQA4U"
  secret_key = "h6EPW6UGgBJu6FYtVZ9p6bJDiIOXYmritXd1Cxj+"
  token = "FwoGZXIvYXdzEHsaDKMiOg4BDv/5ghNqciK6AVLtFzS8sw1Kw9SmL3fKeu+d1aXd5i1X05Qc8+CDe3WhSXdYdE1a+q8vyFGvn7jGDJqW5ZcrlI03hr7F2lS6mKtxKZK3sdDs2Pi5Z0ExZa3ZqYeZYuL7j2uQ79yiijuMkF30SUzDyR/d1Y9udd0nQvq3iGBzSIcUtdec+4iCXVGYAip+j18PLjGgjHS2wDKE1O4Kq8jee3vK18iNvuKebUHkDdyasqET0113WlA7mmixAQpW1owc3IIUKyj824aaBjItxVYbQ8ott4bnWMUw+nvwT/6FvxShOjE9RvnVs/ojlX9xpNa3e/p+XsH2TIEy"
}

resource "aws_security_group" "demoaccess" {
        name   = "demoaccess"
        vpc_id = local.vpc_id
}

# Create Public Subnet for EC2
resource "aws_subnet" "prod-subnet-public-1" {
  vpc_id                  = local.vpc_id
  cidr_block = "172.31.102.0/24"
  map_public_ip_on_launch = "true" //it makes this a public subnet
  availability_zone       = var.AZ1

}

# Create Private subnet for RDS
resource "aws_subnet" "prod-subnet-private-1" {
  vpc_id                  = local.vpc_id
  cidr_block = "172.31.105.0/24"
  map_public_ip_on_launch = "false" //it makes private subnet
  availability_zone       = var.AZ2

}

# Create second Private subnet for RDS
resource "aws_subnet" "prod-subnet-private-2" {
  vpc_id                  = local.vpc_id
  cidr_block = "172.31.106.0/24"
  map_public_ip_on_launch = "false" //it makes private subnet
  availability_zone       = var.AZ3

}



# Create IGW for internet connection 


# Creating Route table 
resource "aws_route_table" "prod-public-crt" {
  vpc_id = local.vpc_id

  route {
    //associated subnet can reach everywhere
    cidr_block = "0.0.0.0/0"
    //CRT uses this IGW to reach internet
    gateway_id = local.prodigw_id
  }


}


# Associating route tabe to public subnet
resource "aws_route_table_association" "prod-crta-public-subnet-1" {
  subnet_id      = aws_subnet.prod-subnet-public-1.id
  route_table_id = aws_route_table.prod-public-crt.id
}



//security group for EC2

resource "aws_security_group" "ec2_allow_rule" {


  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "MYSQL/Aurora"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  vpc_id = local.vpc_id
  tags = {
    Name = "allow ssh,http,https"
  }
}


# Security group for RDS
resource "aws_security_group" "RDS_allow_rule" {
  vpc_id = local.vpc_id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = ["${aws_security_group.ec2_allow_rule.id}"]
  }
  # Allow all outbound traffic.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "allow ec2"
  }

}

# Create RDS Subnet group
resource "aws_db_subnet_group" "RDS_subnet_grp" {
  subnet_ids = ["${aws_subnet.prod-subnet-private-1.id}", "${aws_subnet.prod-subnet-private-2.id}"]
}

# Create RDS instance
resource "aws_db_instance" "wordpressdb" {
  allocated_storage      = 10
  engine                 = "mysql"
  engine_version         = "5.7"
  instance_class         = var.instance_class
  db_subnet_group_name   = aws_db_subnet_group.RDS_subnet_grp.id
  vpc_security_group_ids = [aws_security_group.demoaccess.id]
  name                   = var.database_name
  username               = var.database_user
  password               = var.database_password
  skip_final_snapshot    = true
}

# change USERDATA varible value after grabbing RDS endpoint info
data "template_file" "playbook" {
  template = file("${path.module}/playbook_word.yml")
  vars = {
    db_username      = "${var.database_user}"
    db_user_password = "${var.database_password}"
    db_name          = "${var.database_name}"
    db_RDS           = "${aws_db_instance.wordpressdb.endpoint}"
  }
}


# Create EC2 ( only after RDS is provisioned)
resource "aws_instance" "wordpressec2" {
  ami             = local.ami_id
  instance_type   = var.instance_type
  subnet_id       = aws_subnet.prod-subnet-public-1.id
  security_groups = ["${aws_security_group.ec2_allow_rule.id}"]
  
  key_name = local.key_name
  tags = {
    Name = "Wordpress.web"
  }
  connection {
    type = "ssh"
    host = self.public_ip
    user = local.ssh_user
    private_key = file(local.private_key_path)
    timeout = "4m"
  }

  provisioner "remote-exec" {
    inline = [
      "hostname"
    ]
  }
  

 # Run script to update python on remote client
  provisioner "remote-exec" {
     
     inline = ["sudo yum update -y","sudo yum install python3 -y", "echo Done!"]
   
  }

# Play ansiblw playbook
  provisioner "local-exec" {
     command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -u ec2-user -i '${aws_eip.eip.public_ip},' --private-key ${var.PRIV_KEY_PATH}  playbook_word.yml"
     
}

  # this will stop creating EC2 before RDS is provisioned
  depends_on = [aws_db_instance.wordpressdb]
}

# Sends your public key to the instance

# creating Elastic IP for EC2
resource "aws_eip" "eip" {
  instance = aws_instance.wordpressec2.id

}

output "IP" {
  value = aws_eip.eip.public_ip
}
output "RDS-Endpoint" {
  value = aws_db_instance.wordpressdb.endpoint
}

output "INFO" {
  value = "AWS Resources and Wordpress has been provisioned. Go to http://${aws_eip.eip.public_ip}"
}

# Save Rendered playbook content to local file




