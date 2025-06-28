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

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = "3.35.4"
}

resource "null_resource" "argocd_crds_ready" {
  depends_on = [helm_release.argocd]

  provisioner "local-exec" {
    command = <<EOT
      echo "⏳ Waiting for ArgoCD Application CRD to be installed..."
      for i in {1..30}; do
        kubectl get crd applications.argoproj.io >/dev/null 2>&1 && break
        echo "Waiting 5s for CRD..."
        sleep 5
      done
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

resource "kubernetes_manifest" "argocd_nginx_app" {
  depends_on = [
    null_resource.argocd_crds_ready
  ]
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "nginx-app"
      namespace = kubernetes_namespace.argocd.metadata[0].name
    }
    spec = {
      destination = {
        namespace = "default"
        server    = "https://kubernetes.default.svc"
      }
      project = "default"
      source = {
        path = "apps/argocd/nginx"
        repoURL = "https://github.com/justrunme/gitops-duel-argocd-vs-flux.git"
        targetRevision = "HEAD"
      }
      syncPolicy = {
        automated = {
          prune = true
          selfHeal = true
        }
      }
    }
  }
}

resource "kubernetes_manifest" "argocd_helm_nginx_app" {
  depends_on = [
    null_resource.argocd_crds_ready
  ]
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "helm-nginx-app"
      namespace = kubernetes_namespace.argocd.metadata[0].name
    }
    spec = {
      destination = {
        namespace = "default"
        server    = "https://kubernetes.default.svc"
      }
      project = "default"
      source = {
        path = "apps/argocd/helm-nginx"
        repoURL = "https://github.com/justrunme/gitops-duel-argocd-vs-flux.git"
        targetRevision = "HEAD"
        helm = {
          valueFiles = [
            "values.yaml"
          ]
        }
      }
      syncPolicy = {
        automated = {
          prune = true
          selfHeal = true
        }
      }
    }
  }
}
