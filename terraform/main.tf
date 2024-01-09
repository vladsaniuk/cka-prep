# tomap & merge to add kv to map
resource "aws_vpc" "vpc" {
  cidr_block         = "10.0.0.0/16"
  enable_dns_support = true
  tags               = tomap(merge({ Name = "VPC-${var.env}-env" }, var.tags))
}

# for_each on kv map
resource "aws_subnet" "public_subnets" {
  for_each          = var.public_subnets
  availability_zone = each.key
  cidr_block        = each.value
  vpc_id            = aws_vpc.vpc.id
  #   tags              = tomap(merge({ Name = "Public-subnet-${each.key}-${var.env}-env" }, { "kubernetes.io/role/elb" = "1" }, var.tags))
  tags = tomap(merge({ Name = "Public-subnet-${each.key}-${var.env}-env" }, var.tags))
}

resource "aws_subnet" "private_subnets" {
  for_each          = var.private_subnets
  availability_zone = each.key
  cidr_block        = each.value
  vpc_id            = aws_vpc.vpc.id
  #   tags              = tomap(merge({ Name = "Private-subnet-${each.key}-${var.env}-env" }, { "kubernetes.io/role/internal-elb" = "1" }, { "kubernetes.io/cluster/${var.cluster_name}" = "shared" }, { "karpenter.sh/discovery" = "${var.cluster_name}" }, var.tags))
  tags = tomap(merge({ Name = "Private-subnet-${each.key}-${var.env}-env" }, var.tags))
}

# Export subnets IDs as array to reference it going forward
locals {
  private_subnets_ids = [for subnet in aws_subnet.private_subnets : subnet.id]
  public_subnets_ids  = [for subnet in aws_subnet.public_subnets : subnet.id]
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  tags   = tomap(merge({ Name = "IGW-${var.env}-env" }, var.tags))
}

# depends_on
resource "aws_eip" "nat_ip" {
  domain = "vpc"
  tags   = tomap(merge({ Name = "NAT-IP-${var.env}-env" }, var.tags))
  depends_on = [
    aws_internet_gateway.igw
  ]
}

# Reference subnet ID created by for_each
resource "aws_nat_gateway" "nat" {
  allocation_id     = aws_eip.nat_ip.allocation_id
  connectivity_type = "public"
  subnet_id         = local.public_subnets_ids[0]
  tags              = tomap(merge({ Name = "NAT-${var.env}-env" }, var.tags))
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = tomap(merge({ Name = "Public-route-${var.env}-env" }, var.tags))
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = tomap(merge({ Name = "Private-route-${var.env}-env" }, var.tags))
}

# Pass for_each from subnets to route table associations
resource "aws_route_table_association" "public_routes_to_subnets" {
  for_each       = aws_subnet.public_subnets
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_routes_to_subnets" {
  for_each       = aws_subnet.private_subnets
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_route_table.id
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_key_pair" "ec2_ssh_key" {
  key_name   = "ec2-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "aws_security_group" "ssh" {
  name   = "ssh"
  vpc_id = aws_vpc.vpc.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Reference: https://kubernetes.io/docs/reference/networking/ports-and-protocols/ 
resource "aws_security_group" "control_plane" {
  name   = "control-plane"
  vpc_id = aws_vpc.vpc.id

  ingress {
    description = "Kubernetes API server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "etcd server client API"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.vpc.cidr_block]
  }

  ingress {
    description = "Kubelet API"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.vpc.cidr_block]
  }

  ingress {
    description = "kube-scheduler"
    from_port   = 10259
    to_port     = 10259
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.vpc.cidr_block]
  }

  ingress {
    description = "kube-controller-manager"
    from_port   = 10257
    to_port     = 10257
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.vpc.cidr_block]
  }

  ingress {
    description = "Weave CNI - TCP"
    from_port   = 6783
    to_port     = 6783
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.vpc.cidr_block]
  }

  ingress {
    description = "Weave CNI - UDP"
    from_port   = 6783
    to_port     = 6784
    protocol    = "udp"
    cidr_blocks = [aws_vpc.vpc.cidr_block]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "node" {
  name   = "node"
  vpc_id = aws_vpc.vpc.id

  ingress {
    description = "Kubelet API"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.vpc.cidr_block]
  }

  ingress {
    description = "NodePort Services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Weave CNI - TCP"
    from_port   = 6783
    to_port     = 6783
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.vpc.cidr_block]
  }

  ingress {
    description = "Weave CNI - UDP"
    from_port   = 6783
    to_port     = 6784
    protocol    = "udp"
    cidr_blocks = [aws_vpc.vpc.cidr_block]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# shuffle subnets to place EC2 in
resource "random_shuffle" "control_plane_public_subnets" {
  input        = local.public_subnets_ids
  result_count = 1
}

resource "aws_instance" "control_plane" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.small"
  associate_public_ip_address = true
  key_name                    = aws_key_pair.ec2_ssh_key.key_name
  subnet_id                   = random_shuffle.control_plane_public_subnets.result[0]
  user_data                   = file("userdata.sh")
  vpc_security_group_ids      = [aws_security_group.ssh.id, aws_security_group.control_plane.id]
  tags                        = tomap(merge({ Name = "control-plane-${var.env}" }, var.tags))
}

resource "null_resource" "control_plane_init" {
  # trigger changes if control plance EC2 change
  triggers = {
    control_plane_ip = aws_instance.control_plane.public_ip
  }

  # wait for EC2 to be available
  provisioner "local-exec" {
    command = "aws ec2 wait instance-status-ok --instance-ids ${aws_instance.control_plane.id}"
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("~/.ssh/id_rsa")
    host        = aws_instance.control_plane.public_ip
  }

  provisioner "remote-exec" {
    script = "${path.module}/control_plane.sh"
  }

  # grab kubeadm join command for nodes
  provisioner "local-exec" {
    command = "ssh -o StrictHostKeyChecking=no ubuntu@${aws_instance.control_plane.public_ip} \"kubeadm token create --print-join-command\" > ${path.module}/node_join.sh"
  }
}

resource "random_shuffle" "node_public_subnets" {
  count        = var.nodes_count
  input        = local.public_subnets_ids
  result_count = 1
}

resource "aws_instance" "node" {
  count                       = var.nodes_count
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3a.medium"
  associate_public_ip_address = true
  key_name                    = aws_key_pair.ec2_ssh_key.key_name
  subnet_id                   = random_shuffle.node_public_subnets[count.index].result[0]
  user_data                   = file("userdata.sh")
  vpc_security_group_ids      = [aws_security_group.ssh.id, aws_security_group.node.id]
  tags                        = tomap(merge({ Name = "node-${var.env}-${count.index}" }, var.tags))
}

resource "null_resource" "node_join" {
  count = var.nodes_count
  triggers = {
    node_ip = aws_instance.node[count.index].public_ip
  }

  # wait for EC2 to be available
  provisioner "local-exec" {
    command = "aws ec2 wait instance-status-ok --instance-ids ${aws_instance.node[count.index].id}"
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("~/.ssh/id_rsa")
    host        = aws_instance.node[count.index].public_ip
  }

  # copy script with kubeadm join command
  provisioner "file" {
    source      = "${path.module}/node_join.sh"
    destination = "/tmp/node_join.sh"
  }

  provisioner "remote-exec" {
    script = "${path.module}/node.sh"
  }

  depends_on = [
    null_resource.control_plane_init
  ]
}

output "control_plane_ips" {
  value = aws_instance.control_plane.public_ip
}

output "node_ips" {
  value = aws_instance.node[*].public_ip
}
