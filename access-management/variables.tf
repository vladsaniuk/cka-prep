variable "tags" {
  description = "Map of tags from root module"
  type        = map(string)
  default = {
    Project = "cka-practice"
  }
}
