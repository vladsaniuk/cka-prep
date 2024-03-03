variable "service" {
  description = "User and role object"
  type = object({
    name      = string
    namespace = string
  })
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
