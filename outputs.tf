output "argocd_namespace" {
  description = "ArgoCD namespace name"
  value       = var.argocd_namespace
}

output "flux_namespace" {
  description = "FluxCD namespace name"
  value       = var.flux_namespace
}

output "git_repository_url" {
  description = "Git repository URL being used"
  value       = var.git_repository_url
}

output "access_instructions" {
  description = "Instructions to access the deployed services"
  value = <<-EOT
    
    ===========================================
    GitOps Duel - Access Instructions
    ===========================================
    
    1. ArgoCD UI:
       kubectl port-forward svc/argocd-server -n ${var.argocd_namespace} 8080:80
       Then open: http://localhost:8080
       Login: admin / (get password with: kubectl -n ${var.argocd_namespace} get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    
    2. Check Flux status:
       flux get all -A
    
    3. UI Dashboard (if deployed):
       kubectl port-forward service/ui-frontend 8082:80 -n ${var.target_namespace}
       Then open: http://localhost:8082
    
    4. Monitor applications:
       kubectl get applications -n ${var.argocd_namespace}
       kubectl get kustomizations -n ${var.flux_namespace}
    
    ===========================================
  EOT
}