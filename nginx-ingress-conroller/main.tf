locals {
  namespace_name = "nginx-ingress-controller"
}

# Get self-managed cluster details
data "terraform_remote_state" "cluster" {
  backend = "s3"
  config = {
    bucket         = "vlad-sanyuk-tfstate-bucket-dev"
    key            = "cka/cluster-bootstrap/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "state_lock"
  }
}

# Create namespace for Nginx Ingress Controller
resource "kubernetes_namespace_v1" "nginx_ingress_controller" {
  metadata {
    name = local.namespace_name
  }
}

# Install Nginx Ingress Controller
resource "helm_release" "nginx_ingress_controller" {
  name       = "nginx-ingress-controller"
  namespace  = kubernetes_namespace_v1.nginx_ingress_controller.metadata[0].name
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  wait       = false

  set {
    name  = "controller.admissionWebhooks.failurePolicy"
    value = "Ignore"
  }
}

data "kubernetes_service_v1" "nginx_ingress_controller" {
  metadata {
    name      = "nginx-ingress-controller-ingress-nginx-controller"
    namespace = kubernetes_namespace_v1.nginx_ingress_controller.metadata[0].name
  }

  depends_on = [helm_release.nginx_ingress_controller]
}

resource "aws_security_group" "public_lb" {
  name   = "public-load-balancer-sg"
  vpc_id = data.terraform_remote_state.cluster.outputs.vpc_id

  ingress {
    description = "Public LB, HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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

# Create LB
resource "aws_lb" "public_lb" {
  name                             = "public-load-balancer"
  enable_cross_zone_load_balancing = true
  load_balancer_type               = "application"
  internal                         = false
  security_groups                  = [aws_security_group.public_lb.id]
  subnets                          = data.terraform_remote_state.cluster.outputs.public_subnets_ids

  tags = var.tags
}

resource "aws_lb_target_group" "http" {
  name     = "public-lb-target-group-http"
  port     = [for port in data.kubernetes_service_v1.nginx_ingress_controller.spec.0.port : port.node_port if port.name == "http"][0]
  protocol = "HTTP"
  vpc_id   = data.terraform_remote_state.cluster.outputs.vpc_id

  health_check {
    healthy_threshold   = 2
    interval            = 20
    matcher             = "200-299"
    path                = "/"
    port                = [for port in data.kubernetes_service_v1.nginx_ingress_controller.spec.0.port : port.node_port if port.name == "http"][0]
    protocol            = "HTTP"
    timeout             = 10
    unhealthy_threshold = 5
  }

  tags = var.tags
}

resource "aws_lb_target_group_attachment" "worker_nodes_http" {
  for_each = toset(data.terraform_remote_state.cluster.outputs.worker_nodes_ids)

  target_group_arn = aws_lb_target_group.http.arn
  target_id        = each.value
  port             = [for port in data.kubernetes_service_v1.nginx_ingress_controller.spec.0.port : port.node_port if port.name == "http"][0]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.public_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "forward"

    forward {
      target_group {
        arn    = aws_lb_target_group.http.arn
        weight = 999
      }

      stickiness {
        duration = 300
      }
    }
  }
}
