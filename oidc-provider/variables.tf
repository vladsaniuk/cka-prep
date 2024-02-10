variable "tags" {
  description = "Map of tags from root module"
  type        = map(string)
  default = {
    Project = "cka-practice"
  }
}

variable "cert_manager_version" {
  description = "cert-manager version to use"
  type        = string
  default     = "v1.14.2"
}

variable "amazon_eks_pod_identity_webhook_image" {
  description = "Amazon EKS Pod Identity Webhook image to use"
  type        = string
  default     = "amazon/amazon-eks-pod-identity-webhook:latest"
}

variable "audiences" {
  description = "Audiences to use for IRSA"
  type        = string
  default     = "irsa"
}
