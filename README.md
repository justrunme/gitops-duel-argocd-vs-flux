# GitOps Duel: ArgoCD vs Flux

This repository demonstrates a side-by-side comparison of ArgoCD and Flux, two popular GitOps tools for Kubernetes.

## Structure

- `main.tf`: Terraform configuration for deploying ArgoCD and Flux.
- `modules/`: Terraform modules for installing ArgoCD and Flux.
- `apps/`: Sample nginx application for both ArgoCD and Flux.
  - `apps/argocd/nginx/`: Nginx application deployed via ArgoCD using Kustomize.
  - `apps/flux/nginx/`: Nginx application deployed via FluxCD using Kustomize.
  - `apps/flux/helm-nginx/`: Nginx application deployed via FluxCD using a Helm chart.
- `.github/workflows/`: GitHub Actions workflow for testing the setup on a KinD cluster.

## Prerequisites

- Minikube
- Terraform
- kubectl
- flux CLI

## Getting Started

1.  **Clone the repository:**

    ```bash
    git clone https://github.com/your-username/gitops-duel-argocd-vs-flux.git
    cd gitops-duel-argocd-vs-flux
    ```

2.  **Deploy the infrastructure:**

    ```bash
    terraform init
    terraform apply
    ```

3.  **Access the ArgoCD UI:**

    ```bash
    kubectl port-forward svc/argocd-server -n argocd 8080:443
    ```

    Open your browser and navigate to `https://localhost:8080`.

4.  **Verify FluxCD synchronization:**

    ```bash
    flux get all -A
    ```

## Comparison: Helm vs Kustomize

This project demonstrates both Kustomize and Helm for deploying applications. 

- **Kustomize:** Allows you to customize raw, template-free YAML files for multiple purposes, leaving the original YAMLs untouched. It's great for managing variations of applications.
- **Helm:** A package manager for Kubernetes that uses charts to define, install, and upgrade even the most complex Kubernetes applications. Helm charts are templated YAML files that can be easily parameterized.

## ArgoCD vs FluxCD

Both ArgoCD and FluxCD are popular GitOps tools for Kubernetes, but they have different approaches:

- **ArgoCD:** Pull-based GitOps operator. It continuously monitors your Git repositories and automatically synchronizes the desired state of your applications to the cluster. It has a rich UI for visualization and management.
- **FluxCD:** Push-based GitOps operator. It also monitors Git repositories but focuses on a more declarative approach, where the Git repository is the single source of truth. It's more CLI-centric.

## How to Verify Deployments

- **ArgoCD:**
  ```bash
  argocd app list
  ```
  (You might need to install the `argocd` CLI and log in first.)

- **FluxCD:**
  ```bash
  flux get all -A
  ```
  This command will show all FluxCD resources, including GitRepositories, Kustomizations, and HelmReleases, across all namespaces.