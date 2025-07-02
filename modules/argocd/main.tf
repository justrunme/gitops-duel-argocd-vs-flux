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

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  chart      = "argo-cd"
  repository = "https://argoproj.github.io/argo-helm"
  version    = "5.51.6"

  create_namespace = false
  depends_on = [
    kubernetes_namespace.argocd
  ]

  values = [
    yamlencode({
      crds = {
        install = true
      }
      server = {
        service = {
          type = "ClusterIP"
        }
      }
    })
  ]
}



resource "kubernetes_manifest" "argocd_nginx_app" {
  depends_on = [null_resource.argocd_crds_ready]

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
  depends_on = [null_resource.argocd_crds_ready]

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