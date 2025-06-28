terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

resource "null_resource" "flux_install" {
  provisioner "local-exec" {
    command = "flux install --namespace flux-system"
  }
}

resource "null_resource" "flux_sync" {
  provisioner "local-exec" {
    command = <<EOT
      # wait for Flux controllers to be ready
      kubectl wait --for=condition=Available --timeout=120s deployment/source-controller -n flux-system
      kubectl wait --for=condition=Available --timeout=120s deployment/kustomize-controller -n flux-system

      # create Git source
      flux create source git local-repo \
        --url=https://github.com/justrunme/gitops-duel-argocd-vs-flux.git \
        --branch=main \
        --namespace=flux-system

      # create Kustomization
      flux create kustomization nginx \
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