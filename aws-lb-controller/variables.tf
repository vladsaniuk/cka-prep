variable "tags" {
  description = "Map of tags from root module"
  type        = map(string)
  default = {
    Project = "cka-practice"
  }
}

variable "audiences" {
  description = "Audiences to use for IRSA"
  type        = string
  default     = "irsa"
}
