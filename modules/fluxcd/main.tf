terraform {
  required_providers {
    flux = {
      source = "fluxcd/flux"
    }
  }
}

resource "kubernetes_namespace" "flux_system" {
  metadata {
    name = "flux-system"
  }
}

resource "flux_bootstrap_git" "this" {
  namespace = kubernetes_namespace.flux_system.metadata[0].name
  path      = "./apps/flux"
}