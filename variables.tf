variable "argocd_version" {
  description = "Version of ArgoCD Helm chart"
  type        = string
  default     = "9.0.0"
}

variable "flux_version" {
  description = "Version of Flux2 Helm chart"
  type        = string
  default     = "2.14.0"
}

variable "git_repository_url" {
  description = "Git repository URL for GitOps applications"
  type        = string
  default     = "https://github.com/justrunme/gitops-duel-argocd-vs-flux.git"
}

variable "git_branch" {
  description = "Git branch to track"
  type        = string
  default     = "main"
}

variable "argocd_namespace" {
  description = "Namespace for ArgoCD"
  type        = string
  default     = "argocd"
}

variable "flux_namespace" {
  description = "Namespace for FluxCD"
  type        = string
  default     = "flux-system"
}

variable "target_namespace" {
  description = "Target namespace for applications"
  type        = string
  default     = "default"
}