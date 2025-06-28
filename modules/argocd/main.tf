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

resource "null_resource" "argocd_crd_pre_install" {
  provisioner "local-exec" {
    command = <<EOT
      echo "Applying ArgoCD Application CRD directly..."
      curl -sL https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/crds/application-crd.yaml | kubectl apply -f -
      echo "Waiting for CRD to be established..."
      kubectl wait --for=condition=Established crd/applications.argoproj.io --timeout=120s
      echo "CRD established. Sleeping 5s for API server registration..."
      sleep 5
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

resource "helm_release" "argocd" {
  depends_on = [null_resource.argocd_crd_pre_install]
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

resource "kubernetes_manifest" "argocd_nginx_app" {
  depends_on = [helm_release.argocd]

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
  depends_on = [helm_release.argocd]

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
        path           = "apps/argocd/helm-nginx"
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