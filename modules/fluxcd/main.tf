terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

resource "null_resource" "flux_install" {
  provisioner "local-exec" {
    command = "./bin/flux install --namespace flux-system"
  }
}

resource "null_resource" "flux_sync" {
  provisioner "local-exec" {
    command = <<EOT
      ./bin/flux create source git local-repo \
        --url=https://github.com/justrunme/gitops-duel-argocd-vs-flux.git \
        --branch=main \
        --namespace=flux-system

      ./bin/flux create kustomization nginx \
        --source=GitRepository/local-repo \
        --path=./apps/flux/nginx \
        --prune=true \
        --interval=1m \
        --namespace=flux-system
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
  depends_on = [null_resource.flux_install]
}