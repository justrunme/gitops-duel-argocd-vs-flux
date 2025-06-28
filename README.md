# GitOps Duel: ArgoCD vs Flux

![Terraform CI](https://github.com/justrunme/gitops-duel-argocd-vs-flux/actions/workflows/test-kind.yml/badge.svg)

This repository demonstrates a side-by-side comparison of ArgoCD and Flux, two popular GitOps tools for Kubernetes.

## Architecture

This project sets up a Kubernetes cluster (Minikube locally, KinD in CI) and deploys both ArgoCD and FluxCD. It then uses these GitOps tools to deploy sample Nginx applications, showcasing both Kustomize and Helm-based deployments.

## Structure

- `main.tf`: Terraform configuration for deploying ArgoCD and Flux.
- `modules/`: Terraform modules for installing ArgoCD and Flux.
- `apps/`: Sample Nginx applications for both ArgoCD and Flux.
  - `apps/argocd/nginx/`: Nginx application deployed via ArgoCD using Kustomize.
  - `apps/argocd/helm-nginx/`: Nginx application deployed via ArgoCD using a Helm chart (replicas: 2).
  - `apps/flux/nginx/`: Nginx application deployed via FluxCD using Kustomize.
  - `apps/flux/helm-nginx/`: Nginx application deployed via FluxCD using a Helm chart (replicas: 1).
- `.github/workflows/`: GitHub Actions workflow for testing the setup on a KinD cluster.
- `docs/`: Contains screenshots and other documentation.

## Prerequisites

- Minikube
- Terraform
- kubectl
- flux CLI
- argocd CLI (optional, for local verification)

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

## Comparison: Helm vs Kustomize

This project demonstrates both Kustomize and Helm for deploying applications. 

- **Kustomize:** Allows you to customize raw, template-free YAML files for multiple purposes, leaving the original YAMLs untouched. It's great for managing variations of applications.
- **Helm:** A package manager for Kubernetes that uses charts to define, install, and upgrade even the most complex Kubernetes applications. Helm charts are templated YAML files that can be easily parameterized.

## ArgoCD vs FluxCD

Both ArgoCD and FluxCD are popular GitOps tools for Kubernetes, but they have different approaches:

| Feature         | ArgoCD                                       | FluxCD                                         |
| :-------------- | :------------------------------------------- | :--------------------------------------------- |
| **UI**          | Rich, built-in UI for visualization & management | CLI-centric, with optional UI (e.g., Weave GitOps) |
| **Sync Model**  | Pull-based (ArgoCD pulls from Git)           | Push-based (FluxCD pushes to cluster)          |
| **CRD Management** | Manages CRDs as part of applications         | Manages CRDs as part of its own installation   |
| **Helm Support** | Excellent, native Helm chart support         | Excellent, native HelmRelease CRD              |
| **RBAC**        | Granular RBAC within ArgoCD                  | Leverages Kubernetes RBAC                      |
| **Speed**       | Generally fast, immediate sync               | Event-driven, can be slightly delayed          |

## How GitOps Works

GitOps is an operational framework that takes DevOps best practices used for application development, like version control, collaboration, compliance, and CI/CD, and applies them to infrastructure automation. With GitOps, the Git repository is the single source of truth for your desired system state. Any changes to the system state are made by updating the Git repository, and the GitOps tool (ArgoCD or FluxCD in this case) automatically synchronizes the cluster to match the desired state.

## Verification and Debugging Commands

- **ArgoCD:**
  ```bash
  argocd app list
  argocd app get <app-name>
  argocd app logs <app-name>
  ```
  (You might need to install the `argocd` CLI and log in first.)

- **FluxCD:**
  ```bash
  flux get all -A
  flux get kustomizations -A
  flux get helmreleases -A
  ```

- **Kubernetes (General):**
  ```bash
  kubectl get pods -n default
  kubectl get deployments -n default
  kubectl get services -n default
  kubectl get pods -n flux-system
  kubectl get deployments -n flux-system
  kubectl get services -n flux-system
  ```

## ArgoCD UI Screenshot

![ArgoCD UI](./docs/argocd-ui.png)