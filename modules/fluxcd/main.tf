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

      echo " Waiting for HelmRelease CRD to be established..."
      kubectl wait --for=condition=Established crd/helmreleases.helm.toolkit.fluxcd.io --timeout=120s

      echo " Waiting for API group helm.toolkit.fluxcd.io/v2 to become available..."
      for i in {1..30}; do
        if kubectl get --raw="/apis/helm.toolkit.fluxcd.io/v2" >/dev/null 2>&1; then
          echo "✅ API group is available"
          break
        fi
        echo "⏳ API group not ready yet..."
        sleep 5
      done

      echo " Waiting for HelmRelease kind to be discoverable..."
      for i in {1..30}; do
        if kubectl api-resources | grep -q "helmreleases.*helm.toolkit.fluxcd.io"; then
          echo "✅ HelmRelease kind is discoverable"
          break
        fi
        echo "⏳ HelmRelease still not discoverable..."
        sleep 5
      done

      echo "⏳ Verifying HelmRelease kind is fully recognized by kubectl explain..."
      for i in {1..10}; do
        if kubectl explain helmrelease --api-version=helm.toolkit.fluxcd.io/v2 >/dev/null 2>&1; then
          echo "✅ HelmRelease kind is fully recognized"
          break
        fi
        echo "⏳ Still waiting for explain API..."
        sleep 5
      done

      echo " Creating GitRepository source..."
      flux create source git local-repo \
        --url=https://github.com/justrunme/gitops-duel-argocd-vs-flux.git \
        --branch=main \
        --namespace=flux-system

      echo "⏳ Waiting for GitRepository to reconcile..."
      sleep 15

      echo " Applying Kustomization for HelmRelease..."
      flux create kustomization helm-nginx \
        --source=GitRepository/local-repo \
        --path=./apps/flux/helm-nginx \
        --prune=true \
        --interval=1m \
        --namespace=flux-system
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}
