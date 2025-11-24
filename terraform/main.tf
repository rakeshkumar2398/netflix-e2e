# ------------------------- KEY PAIR -------------------------
resource "aws_key_pair" "key_pair" {
  key_name   = "MyKey"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDQmSeyo0K6MzM7ZA0o+jVz+CKXQFv0oQRJmUI12eK3IXBEunPdqKPxY2xHPbspEHlEjL1cUay90KhHjPAeLM3QELeviL6SvxZ3Gcr3ekxwRv5tvIJLnyjdwpuFj0VW4FhKTqLTyxA6ebOks4VZIARwSGAdZEez3A6S8kyi/fmk0s9WL/GQ3HBSjrhMfUPvLlXi5WHSA1PFBVNL1y1AIpfM16BkSfEc5r3SkgI6hXTGZ7MuxYaiPINWGH92GUHv6oEK7nDQ/ig+Ozy9kU7Yo2EeeQwX+49jP5NeB/FMpv9AODUXIq4p+V1KFwrxRATvgqulaM2ZxaV/QOxFkYhAK/DYzzHDi72cRZIfNtk2SsuFhBhPoh01cbxgYa0tytZaHwrwyDTMqi/TqeWKL3khSd/wddW8z4UgA28LCfZnvIm7fJyvpxSCXDZ2WmntsT1EnE6THKDimCkQQtw/Y10dYhIbKarbyWI78Pbj/ujTqVI6HYa1boIammo4ubxm9dbNajE= Rakesh@RAKESH"
}

# ------------------------- VPC -------------------------
resource "aws_vpc" "netflix" {
  cidr_block           = "172.20.0.0/16"
  enable_dns_hostnames = true

  tags = { Name = "netflix" }
}

# ------------------------- SUBNET -------------------------
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.netflix.id
  cidr_block              = "172.20.10.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = { Name = "public-subnet" }
}

# ------------------------- Internet Gateway -------------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.netflix.id

  tags = { Name = "netflix-igw" }
}

# ------------------------- Route Table -------------------------
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.netflix.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "public-route-table" }
}

# ------------------------- Route Table Association -------------------------
resource "aws_route_table_association" "public_rt_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# ------------------------- SECURITY GROUP -------------------------
resource "aws_security_group" "netflix_sg" {
  name        = "netflix-sg"
  vpc_id      = aws_vpc.netflix.id
  description = "SG for Netflix Tools Server"

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 8080
    to_port   = 8080
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 9000
    to_port   = 9000
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = -1
    to_port   = -1
    protocol  = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "netflix-sg" }
}

# ------------------------- EC2 INSTANCE -------------------------
resource "aws_instance" "netflix" {
  ami                    = "ami-0fa3fe0fa7920f68e"  # Amazon Linux 2 AMI (us-east-1)
  instance_type          = "t2.xlarge"
  subnet_id              = aws_subnet.public_subnet.id
  key_name               = aws_key_pair.key_pair.key_name
  vpc_security_group_ids = [aws_security_group.netflix_sg.id]

  connection {
    type        = "ssh"
    host        = self.public_ip
    user        = "ec2-user"
    private_key = file("~/.ssh/id_rsa")
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum update -y",
      "sudo yum install -y wget git docker unzip",
      "sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo",
      "sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key",
      "sudo yum install -y jenkins",
      "sudo systemctl enable jenkins && sudo systemctl start jenkins",
      "sudo systemctl enable docker && sudo systemctl start docker",
      "sudo usermod -aG docker ec2-user",
      "sudo usermod -aG docker jenkins",
      "sudo chmod 666 /var/run/docker.sock",
      "sudo docker run -d --name sonar -p 9000:9000 sonarqube:lts-community",
      "sudo rpm -ivh https://github.com/aquasecurity/trivy/releases/download/v0.18.3/trivy_0.18.3_Linux-64bit.rpm || true",

      # ---------- Install kubectl ----------
      "curl -LO https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl",
      "curl -LO https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256",
      "echo \"$(cat kubectl.sha256) kubectl\" | sha256sum --check",
      "sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl",

      # ---------- Install eksctl ----------
      "curl --silent --location \"https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz\" | tar xz -C /tmp",
      "sudo mv /tmp/eksctl /usr/local/bin/"
    ]
  }

  tags = { Name = "Netflix-Server" }
}

