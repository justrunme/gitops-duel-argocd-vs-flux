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
  depends_on = [kubernetes_namespace.argocd]

  values = [
    yamlencode({
      crds = {
        install = true
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
        targetRevision = "main"
        path           = "apps/argocd/helm-nginx/nginx"
        helm = {
          values = <<-EOT
            replicaCount: 2
          EOT
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "default"
      }
    }
  }
}

