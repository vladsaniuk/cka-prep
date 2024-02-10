variable "public_subnets" {
  description = "Map of AZ = CIDR block for public subnets"
  type        = map(string)
  default = {
    us-east-1a = "10.0.0.0/19"
    us-east-1b = "10.0.32.0/19"
    us-east-1c = "10.0.64.0/19"
    us-east-1d = "10.0.96.0/19"
  }
}

variable "private_subnets" {
  description = "Map of AZ = CIDR block for private subnets"
  type        = map(string)
  default = {
    us-east-1a = "10.0.128.0/19"
    us-east-1b = "10.0.160.0/19"
    us-east-1c = "10.0.192.0/19"
    us-east-1d = "10.0.224.0/19"
  }
}

variable "tags" {
  description = "Map of tags from root module"
  type        = map(string)
  default = {
    Project = "cka-practice"
  }
}

variable "env" {
  description = "Development environment"
  type        = string
  default     = "dev"
}

variable "my_ip" {
  description = "IP var should be provided via tf CLI command execution, i.e. terraform plan -var 'my_ip=192.158.1.38/32'"
  type        = string
}

variable "nodes_count" {
  description = "Count of nodes to be spawned"
  type        = number
  default     = 2
}

variable "cluster_name" {
  description = "Cluster name, that will be used for AWS LBC and Karpenter"
  type        = string
  default     = "k8s-cluster"
}

variable "audiences" {
  description = "Audiences to use for IRSA"
  type        = string
  default     = "irsa"
}
