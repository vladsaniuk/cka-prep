locals {
  bucket_name     = "oidc-provider"
  issuer_hostpath = "s3.${data.aws_region.current.name}.amazonaws.com/${local.bucket_name}"
}

data "aws_region" "current" {}

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
  tags              = tomap(merge({ Name = "Public-subnet-${each.key}-${var.env}-env" }, { "kubernetes.io/role/elb" = "1", "kubernetes.io/cluster/${var.cluster_name}" = "owned" }, var.tags))
}

resource "aws_subnet" "private_subnets" {
  for_each          = var.private_subnets
  availability_zone = each.key
  cidr_block        = each.value
  vpc_id            = aws_vpc.vpc.id
  tags              = tomap(merge({ Name = "Private-subnet-${each.key}-${var.env}-env" }, { "kubernetes.io/role/internal-elb" = "1" }, { "kubernetes.io/cluster/${var.cluster_name}" = "owned" }, { "karpenter.sh/discovery" = "${var.cluster_name}" }, var.tags))
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
    # k8s API server are available from internal network and my IP
    cidr_blocks = [aws_vpc.vpc.cidr_block, var.my_ip]
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

  # ingress {
  #   description = "Nginx Ingress Controller - ValidatingWebhookConfiguration"
  #   from_port   = 8443
  #   to_port     = 8443
  #   protocol    = "tcp"
  #   cidr_blocks = [aws_vpc.vpc.cidr_block]
  # }

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

  tags = tomap(merge({ Name = "node-sg-${var.env}", "kubernetes.io/cluster/${var.cluster_name}" = "owned" }, var.tags))
}

# shuffle subnets to place EC2 in
resource "random_shuffle" "control_plane_public_subnets" {
  input        = local.public_subnets_ids
  result_count = 1
}

# Configure IAM permissions for AWS Cloud Provider (Cloud Controller Manager) for control plane
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "control_plane" {
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
  description        = "AWS Cloud Provider (Cloud Controller Manager) role for ${var.cluster_name} cluster control plane"
  name               = "AWS-CCM-${var.cluster_name}-control-plane"
  path               = "/"
  tags               = var.tags
}

data "aws_iam_policy_document" "control_plane" {
  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeTags",
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVolumes",
      "ec2:DescribeAvailabilityZones",
      "ec2:CreateSecurityGroup",
      "ec2:CreateTags",
      "ec2:CreateVolume",
      "ec2:ModifyInstanceAttribute",
      "ec2:ModifyVolume",
      "ec2:AttachVolume",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CreateRoute",
      "ec2:DeleteRoute",
      "ec2:DeleteSecurityGroup",
      "ec2:DeleteVolume",
      "ec2:DetachVolume",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:DescribeVpcs",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:AttachLoadBalancerToSubnets",
      "elasticloadbalancing:ApplySecurityGroupsToLoadBalancer",
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateLoadBalancerPolicy",
      "elasticloadbalancing:CreateLoadBalancerListeners",
      "elasticloadbalancing:ConfigureHealthCheck",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:DeleteLoadBalancerListeners",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DetachLoadBalancerFromSubnets",
      "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
      "elasticloadbalancing:SetLoadBalancerPoliciesForBackendServer",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeLoadBalancerPolicies",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:SetLoadBalancerPoliciesOfListener",
      "iam:CreateServiceLinkedRole",
      "kms:DescribeKey"
    ]
  }
}

resource "aws_iam_policy" "control_plane" {
  policy      = data.aws_iam_policy_document.control_plane.json
  description = "AWS Cloud Provider (Cloud Controller Manager) policy for ${var.cluster_name} cluster control plane"
  name        = "AWS-CCM-policy-${var.cluster_name}-control-plane"
  path        = "/"
  tags        = var.tags
}

resource "aws_iam_policy_attachment" "control_plane" {
  name       = "ccm-policy-to-role-attachment"
  roles      = [aws_iam_role.control_plane.name]
  policy_arn = aws_iam_policy.control_plane.arn
}

# S3 bucket for etcd backups
resource "aws_s3_bucket" "etcd_backup" {
  bucket        = "etcd-backup-${var.env}-${random_string.bucket_suffix.result}"
  force_destroy = true

  tags = var.tags
}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket_versioning" "etcd_backup_versioning" {
  bucket = aws_s3_bucket.etcd_backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_ownership_controls" "etcd_backup_ownership" {
  bucket = aws_s3_bucket.etcd_backup.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "etcd_backup_public_access_block" {
  bucket = aws_s3_bucket.etcd_backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "etcd_backup_encryption" {
  bucket = aws_s3_bucket.etcd_backup.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = "aws/s3"
    }
    bucket_key_enabled = true
  }
}

data "aws_iam_policy_document" "etcd_backup" {
  statement {
    sid    = ""
    effect = "Allow"
    resources = [
      aws_s3_bucket.etcd_backup.arn,
      "${aws_s3_bucket.etcd_backup.arn}/*"
    ]

    actions = [
      "s3:PutObject",
      "s3:GetObject"
    ]
  }

  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["*"] # this is required for ListAllMyBuckets, but we only limit it to this specific call

    actions = [
      "s3:ListAllMyBuckets"
    ]
  }
}

resource "aws_iam_policy" "etcd_backup" {
  policy      = data.aws_iam_policy_document.etcd_backup.json
  description = "etcd backup policy for ${var.cluster_name} cluster control plane"
  name        = "etcd-backup-policy-${var.cluster_name}-control-plane"
  path        = "/"
  tags        = var.tags
}

resource "aws_iam_policy_attachment" "etcd_backup" {
  name       = "etcd-backup-policy-to-role-attachment"
  roles      = [aws_iam_role.control_plane.name]
  policy_arn = aws_iam_policy.etcd_backup.arn
}

resource "aws_iam_instance_profile" "control_plane" {
  name = "control-plane-profile"
  role = aws_iam_role.control_plane.name
}

resource "aws_instance" "control_plane" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.small"
  associate_public_ip_address = true
  key_name                    = aws_key_pair.ec2_ssh_key.key_name
  subnet_id                   = random_shuffle.control_plane_public_subnets.result[0]
  user_data                   = file("userdata.sh")
  vpc_security_group_ids      = [aws_security_group.ssh.id, aws_security_group.control_plane.id]
  iam_instance_profile        = aws_iam_instance_profile.control_plane.name
  tags                        = tomap(merge({ Name = "control-plane-${var.env}", "kubernetes.io/cluster/${var.cluster_name}" = "owned" }, var.tags))
}

# Generate config for kubeadm, so API server will be reachable from my IP and add config for IRSA
# set cloud-provider to external on api-server and controller-manager
resource "local_file" "kubeadm_config" {
  filename        = "${path.module}/kubeadm_config.yaml"
  file_permission = "0755"

  content = <<-EOF
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
clusterName: ${var.cluster_name}
apiServer:
  certSANs:
  - ${aws_instance.control_plane.public_ip}
  - ${aws_instance.control_plane.private_ip}
  extraArgs:
    api-audiences: ${var.audiences}
    service-account-issuer: https://${local.issuer_hostpath}
    cloud-provider: external
controllerManager:
  extraArgs:
    cloud-provider: external
  EOF
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
    inline = [
      "sudo mkdir -p /opt/etcd-backup",
      "sudo chown ubuntu:ubuntu /opt/etcd-backup"
    ]
  }

  provisioner "file" {
    source      = "${path.module}/etcd-backup"
    destination = "/opt"
  }

  provisioner "file" {
    source      = "${path.module}/kubeadm_config.yaml"
    destination = "/tmp/kubeadm_config.yaml"
  }

  provisioner "remote-exec" {
    script = "${path.module}/control_plane.sh"
  }

  # grab kubeadm join command for nodes and kubeconfig for k8s provider
  provisioner "local-exec" {
    command = "ssh -o StrictHostKeyChecking=no ubuntu@${aws_instance.control_plane.public_ip} \"kubeadm token create --print-join-command\" > ${path.module}/node_join.sh"
  }

  depends_on = [aws_s3_bucket.etcd_backup]
}

resource "random_shuffle" "node_public_subnets" {
  count        = var.nodes_count
  input        = local.public_subnets_ids
  result_count = 1
}

# Configure IAM permissions for AWS Cloud Provider (Cloud Controller Manager) for node
resource "aws_iam_role" "node" {
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
  description        = "AWS Cloud Provider (Cloud Controller Manager) role for ${var.cluster_name} cluster node"
  name               = "AWS-CCM-${var.cluster_name}-node"
  path               = "/"
  tags               = var.tags
}

data "aws_iam_policy_document" "node" {
  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetRepositoryPolicy",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "ecr:BatchGetImage"
    ]
  }
}

resource "aws_iam_policy" "node" {
  policy      = data.aws_iam_policy_document.node.json
  description = "AWS Cloud Provider (Cloud Controller Manager) policy for ${var.cluster_name} for node"
  name        = "AWS-CCM-policy-${var.cluster_name}-node"
  path        = "/"
  tags        = var.tags
}

resource "aws_iam_policy_attachment" "node" {
  name       = "ccm-policy-to-role-attachment"
  roles      = [aws_iam_role.node.name]
  policy_arn = aws_iam_policy.node.arn
}

resource "aws_iam_instance_profile" "node" {
  name = "node_profile"
  role = aws_iam_role.node.name
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
  iam_instance_profile        = aws_iam_instance_profile.node.name
  tags                        = tomap(merge({ Name = "node-${var.env}-${count.index}", "kubernetes.io/cluster/${var.cluster_name}" = "owned" }, var.tags))
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

resource "null_resource" "get_kubeconfig" {
  # trigger changes if kubeconfig changes, or doesn't exist
  triggers = {
    kubeconfig = aws_instance.control_plane.public_ip
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("~/.ssh/id_rsa")
    host        = aws_instance.control_plane.public_ip
  }

  # copy kubeconfig file from remote to local
  provisioner "local-exec" {
    command = <<-EOF
      ssh -o StrictHostKeyChecking=no ubuntu@${aws_instance.control_plane.public_ip} "sudo cat /etc/kubernetes/admin.conf" > ${path.module}/kubeconfig
      KUBECONFIG=kubeconfig kubectl config set clusters.${var.cluster_name}.server https://${aws_instance.control_plane.public_ip}:6443
      ssh -o StrictHostKeyChecking=no ubuntu@${aws_instance.control_plane.public_ip} "sudo cat /etc/kubernetes/pki/sa.pub" > ${path.module}/sa-signer.key.pub
      chmod 400 sa-signer.key.pub
      ssh -o StrictHostKeyChecking=no ubuntu@${aws_instance.control_plane.public_ip} "sudo cat /etc/kubernetes/pki/ca.crt" > ${path.module}/ca.crt
    EOF
  }

  depends_on = [
    null_resource.control_plane_init
  ]
}
