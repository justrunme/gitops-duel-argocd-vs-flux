terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    helm = {
      source = "hashicorp/helm"
    }
    null = {
      source = "hashicorp/null"
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
  depends_on = [
    kubernetes_namespace.flux
  ]

  set = [
    {
      name  = "installCRDs"
      value = "true"
    },
    {
      name  = "helmController.enabled"
      value = "true"
    }
  ]
}

