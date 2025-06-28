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

resource "null_resource" "flux_crds_ready" {
  depends_on = [helm_release.flux]

  provisioner "local-exec" {
    command = <<EOT
      echo "⏳ Waiting for FluxCD HelmRelease CRD to be established..."
      kubectl wait --for=condition=Established crd/helmreleases.helm.toolkit.fluxcd.io --timeout=90s
      echo "✅ FluxCD HelmRelease CRD ready"
      echo "--- FluxCD HelmRelease CRD details ---"
      kubectl get crd helmreleases.helm.toolkit.fluxcd.io -o yaml
      echo "------------------------------------"
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

resource "null_resource" "flux_sync" {
  depends_on = [
    helm_release.flux,
    null_resource.flux_crds_ready
  ]

  provisioner "local-exec" {
    command = <<EOT
      set -e

      echo " Waiting for Flux controllers to become ready..."
      kubectl wait --for=condition=Available --timeout=120s deployment/source-controller -n flux-system
      kubectl wait --for=condition=Available --timeout=120s deployment/kustomize-controller -n flux-system
      kubectl wait --for=condition=Available --timeout=120s deployment/helm-controller -n flux-system

      echo "⏳ Waiting for HelmRelease CRD to be established..."
      kubectl wait --for=condition=Established crd/helmreleases.helm.toolkit.fluxcd.io --timeout=120s

      echo " Verifying API availability for helm.toolkit.fluxcd.io..."
      for i in {1..20}; do
        if kubectl api-resources --api-group=helm.toolkit.fluxcd.io | grep -q HelmRelease; then
          echo '✅ API is now available'
          break
        fi
        echo "⏳ API not available yet, sleeping..."
        sleep 5
      done

      echo " Creating GitRepository source"
      flux create source git local-repo \
        --url=https://github.com/justrunme/gitops-duel-argocd-vs-flux.git \
        --branch=main \
        --namespace=flux-system

      echo " Creating HelmRelease"
      flux create helmrelease helm-nginx \
        --source=GitRepository/local-repo \
        --chart=./apps/flux/helm-nginx \
        --interval=1m \
        --namespace=flux-system
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}
