variable "user" {
  description = "User and role object"
  type = object({
    name      = string
    role      = string
    namespace = optional(string)
  })

  validation {
    condition     = var.user.role == "dev" ? var.user.namespace != null : var.user.namespace == null
    error_message = "When role is dev, namespace should be specified"
  }
}

variable "control_plane_ip" {
  description = "Control plane IP from cluster-bootstrap"
  type        = string
}

variable "cluster_name" {
  description = "Cluster name from cluster-bootstrap"
  type        = string
}

variable "labels" {
  description = "Tags used in cluster"
  type        = map(string)
}
