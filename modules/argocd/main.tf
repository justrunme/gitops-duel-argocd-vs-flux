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

variable "argocd_version" {
  description = "Version of ArgoCD Helm chart"
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

variable "argocd_namespace" {
  description = "Namespace for ArgoCD"
  type        = string
}

variable "target_namespace" {
  description = "Target namespace for applications"
  type        = string
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.argocd_namespace
  }
}

resource "kubernetes_namespace" "target" {
  metadata {
    name = var.target_namespace
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  chart      = "argo-cd"
  repository = "https://argoproj.github.io/argo-helm"
  version    = var.argocd_version
  depends_on = [kubernetes_namespace.argocd]

  values = [
    yamlencode({
      global = {
        domain = "argocd.local"
      }
      crds = {
        install = true
        keep    = true
      }
      configs = {
        params = {
          "server.insecure" = true
        }
        cm = {
          "timeout.reconciliation" = "10s"
        }
      }
    })
  ]
}

resource "null_resource" "argocd_crds_ready" {
  depends_on = [helm_release.argocd]
  provisioner "local-exec" {
    command = "kubectl wait --for=condition=Established crd/applications.argoproj.io --timeout=120s"
  }
}

resource "kubernetes_manifest" "argocd_nginx_app" {
  depends_on = [
    null_resource.argocd_crds_ready,
    kubernetes_namespace.target,
  ]

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "nginx-app"
      namespace = var.argocd_namespace
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.git_repository_url
        targetRevision = var.git_branch
        path           = "apps/argocd/nginx"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.target_namespace
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=true",
          "PrunePropagationPolicy=foreground",
        ]
      }
    }
  }
}

resource "kubernetes_manifest" "argocd_helm_nginx_app" {
  depends_on = [
    null_resource.argocd_crds_ready,
    kubernetes_namespace.target,
  ]

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "helm-nginx-app"
      namespace = var.argocd_namespace
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.git_repository_url
        targetRevision = var.git_branch
        path           = "apps/argocd/helm-nginx/nginx"
        helm = {
          values = <<-EOT
            name: helm-nginx-app
            replicaCount: 2
          EOT
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.target_namespace
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=true",
        ]
      }
    }
  }
}
