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

variable "flux_version" {
  description = "Version of Flux2 Helm chart"
  type        = string
}

variable "git_repository_url" {
  description = "Git repository URL for GitOps applications"
  type        = string
}

variable "git_branch" {
  description = "Git branch to track"
  type        = string
}

variable "flux_namespace" {
  description = "Namespace for FluxCD"
  type        = string
}

variable "target_namespace" {
  description = "Target namespace for applications"
  type        = string
}

resource "kubernetes_namespace" "flux" {
  metadata {
    name = var.flux_namespace
  }
}

resource "helm_release" "flux" {
  name             = "flux2"
  namespace        = kubernetes_namespace.flux.metadata[0].name
  repository       = "https://fluxcd-community.github.io/helm-charts"
  chart            = "flux2"
  version          = var.flux_version
  depends_on       = [kubernetes_namespace.flux]
  set = [{
    name  = "installCRDs"
    value = "true"
  }]
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
      namespace = var.flux_namespace
    }
    spec = {
      interval = "1m"
      url      = var.git_repository_url
      ref = {
        branch = var.git_branch
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
      namespace = var.flux_namespace
    }
    spec = {
      interval = "1m"
      path     = "./apps/flux/nginx"
      prune    = true
      targetNamespace = var.target_namespace
      sourceRef = {
        kind = "GitRepository"
        name = "local-repo"
      }
    }
  }
}
