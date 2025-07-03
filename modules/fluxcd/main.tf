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
  depends_on       = [kubernetes_namespace.flux]
  set = [
    {
      name  = "installCRDs"
      value = "true"
    }
  ]
}

resource "null_resource" "flux_crds_ready" {
  depends_on = [helm_release.flux]
  provisioner "local-exec" {
    command = "kubectl wait --for=condition=Established crd/kustomizations.kustomize.toolkit.fluxcd.io --timeout=120s"
  }
}

resource "kubernetes_manifest" "flux_git_repository" {
  depends_on = [null_resource.flux_crds_ready]
  manifest = {
    apiVersion = "source.toolkit.fluxcd.io/v1"
    kind       = "GitRepository"
    metadata = {
      name      = "local-repo"
      namespace = "flux-system"
    }
    spec = {
      interval = "1m"
      url      = "https://github.com/justrunme/gitops-duel-argocd-vs-flux.git"
      ref = {
        branch = "main"
      }
    }
  }
}

resource "kubernetes_manifest" "flux_kustomization" {
  depends_on = [kubernetes_manifest.flux_git_repository]
  manifest = {
    apiVersion = "kustomize.toolkit.fluxcd.io/v1"
    kind       = "Kustomization"
    metadata = {
      name      = "flux-nginx-app"
      namespace = "flux-system"
    }
    spec = {
      interval = "1m"
      path     = "./apps/flux/nginx"
      prune    = true
      targetNamespace = "default"
      sourceRef = {
        kind = "GitRepository"
        name = "local-repo"
      }
    }
  }
}
