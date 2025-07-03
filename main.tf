module "argocd" {
  source = "./modules/argocd"
  
  argocd_version       = var.argocd_version
  git_repository_url   = var.git_repository_url
  git_branch          = var.git_branch
  argocd_namespace    = var.argocd_namespace
  target_namespace    = var.target_namespace
}

module "fluxcd" {
  source = "./modules/fluxcd"
  
  flux_version       = var.flux_version
  git_repository_url = var.git_repository_url
  git_branch        = var.git_branch
  flux_namespace    = var.flux_namespace
  target_namespace  = var.target_namespace
}