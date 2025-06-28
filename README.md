# GitOps Duel: ArgoCD vs Flux

This repository demonstrates a side-by-side comparison of ArgoCD and Flux, two popular GitOps tools for Kubernetes.

## Structure

- `main.tf`: Terraform configuration for deploying ArgoCD and Flux.
- `modules/`: Terraform modules for installing ArgoCD and Flux.
- `apps/`: Sample nginx application for both ArgoCD and Flux.
- `.github/workflows/`: GitHub Actions workflow for testing the setup on a KinD cluster.

## Prerequisites

- Minikube
- Terraform
- kubectl

## Getting Started

1. **Clone the repository:**

   ```bash
   git clone https://github.com/your-username/gitops-duel-argocd-vs-flux.git
   cd gitops-duel-argocd-vs-flux
   ```

2. **Deploy the infrastructure:**

   ```bash
   terraform init
   terraform apply
   ```

3. **Access the ArgoCD UI:**

   ```bash
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   ```

   Open your browser and navigate to `https://localhost:8080`.

4. **Verify Flux synchronization:**

   ```bash
   kubectl get pods -n flux-system
   kubectl get kustomizations -n flux-system
   ```
