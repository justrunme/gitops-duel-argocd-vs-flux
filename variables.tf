variable "flux_ssh_private_key" {
  description = "SSH private key for FluxCD to access the Git repository"
  type        = string
  sensitive   = true
}