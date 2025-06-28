terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    helm = {
      source = "hashicorp/helm"
    }
  }
}

resource "kubernetes_namespace" "flux" {
  metadata {
    name = "flux-system"
  }
}

resource "helm_release" "flux" {
  name             = "flux2"
  namespace        = kubernetes_namespace.flux.metadata[0].name
  repository       = "https://fluxcd-community.github.io/helm-charts"
  chart            = "flux2"
  version          = "2.11.1"
  create_namespace = false

  set = [
    {
      name  = "installCRDs"
      value = "true"
    }
  ]
}

resource "null_resource" "flux_sync" {
  depends_on = [
    helm_release.flux
  ]

  provisioner "local-exec" {
    command = <<EOT
      kubectl wait --for=condition=Available --timeout=120s deployment/source-controller -n flux-system
      kubectl wait --for=condition=Available --timeout=120s deployment/kustomize-controller -n flux-system

      flux create source git local-repo \
        --url=https://github.com/justrunme/gitops-duel-argocd-vs-flux.git \
        --branch=main \
        --namespace=flux-system

      flux create helmrelease helm-nginx \
        --source=GitRepository/local-repo \
        --chart=./apps/flux/helm-nginx \
        --interval=1m \
        --namespace=flux-system
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}
