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

variable "argocd_target_namespace" {
  description = "Target namespace for Argo CD demo applications"
  type        = string
  default     = "argocd-demo"
}

variable "flux_target_namespace" {
  description = "Target namespace for Flux demo applications"
  type        = string
  default     = "flux-demo"
}

# Kept for backward compatibility with older module call sites / docs.
variable "target_namespace" {
  description = "Deprecated: use argocd_target_namespace / flux_target_namespace"
  type        = string
  default     = "default"
}
