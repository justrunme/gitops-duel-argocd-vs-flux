terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    helm = {
      source = "hashicorp/helm"
    }
    kubectl = {
      source = "gavinbunney/kubectl"
    }
  }
}

locals {
  crd_names = [
    "applications.argoproj.io",
    "appprojects.argoproj.io",
  ]
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = "argocd"
  chart      = "argo-cd"
  repository = "https://argoproj.github.io/argo-helm"
  version    = "5.51.6"

  create_namespace = true

  values = [
    yamlencode({
      server = {
        service = {
          type = "ClusterIP"
        }
      }
    })
  ]
}

data "kubectl_manifest" "argocd_crd" {
  depends_on = [helm_release.argocd]
  count      = length(local.crd_names)
  yaml_body = yamlencode({
    apiVersion = "apiextensions.k8s.io/v1"
    kind       = "CustomResourceDefinition"
    metadata = {
      name = local.crd_names[count.index]
    }
  })
  wait_for = {
    "fields" = {
      "status.acceptedNames.kind" = "Application"
    }
  }
}

resource "kubernetes_manifest" "argocd_nginx_app" {
  depends_on = [data.kubectl_manifest.argocd_crd]

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "nginx-app"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/justrunme/gitops-duel-argocd-vs-flux.git"
        targetRevision = "HEAD"
        path           = "apps/argocd/nginx"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "default"
      }
      syncPolicy = {
        automated = {
          prune     = true
          selfHeal  = true
        }
      }
    }
  }
}

resource "kubernetes_manifest" "argocd_helm_nginx_app" {
  depends_on = [data.kubectl_manifest.argocd_crd]

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "helm-nginx-app"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/justrunme/gitops-duel-argocd-vs-flux.git"
        targetRevision = "HEAD"
        path           = "charts/nginx"
        helm = {
          values = <<-EOT
            replicaCount: 2
            image:
              repository: nginx
              tag: "1.25.2"
              pullPolicy: IfNotPresent
            service:
              type: ClusterIP
              port: 80
          EOT
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "default"
      }
      syncPolicy = {
        automated = {
          prune     = true
          selfHeal  = true
        }
      }
    }
  }
}