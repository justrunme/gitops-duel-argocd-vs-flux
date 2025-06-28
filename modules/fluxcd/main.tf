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
    command = "./bin/flux create source git local-repo --url=ssh://git@github.com/justrunme/gitops-duel-argocd-vs-flux.git --branch=main --namespace=flux-system --secret-ref=flux-system --private-key=${var.flux_ssh_private_key} && ./bin/flux create kustomization nginx --source=GitRepository/local-repo --path=./apps/flux/nginx --prune=true --interval=1m --namespace=flux-system"
  }
  depends_on = [null_resource.flux_install]
}
