# GitOps Duel: ArgoCD vs Flux

![GitOps Duel CI](https://github.com/justrunme/gitops-duel-argocd-vs-flux/actions/workflows/test-kind.yml/badge.svg)

This repository serves as a comprehensive demonstration and comparison of ArgoCD and Flux, two leading GitOps tools for Kubernetes. It showcases their distinct approaches to continuous delivery, self-healing capabilities, and provides a visual interface for comparing application states.

## ✨ Key Features

*   **Side-by-Side Comparison:** Deploy and manage applications using both ArgoCD and Flux within the same Kubernetes cluster.
*   **Unified Helm Chart Management:** Transitioned all sample application deployments to Helm charts, demonstrating a consistent approach across both GitOps tools.
*   **Comprehensive CI/CD Pipeline:** A robust GitHub Actions workflow that automates:
    *   KinD cluster provisioning.
    *   Deployment of ArgoCD, Flux, and all sample applications.
    *   Building and deploying a custom UI for manifest comparison.
    *   **Automated Error Simulation:** Tests the self-healing capabilities of ArgoCD and Flux by intentionally introducing discrepancies (e.g., deleting deployments, scaling replicas to zero) and verifying their recovery.
    *   **Detailed Access Information:** Provides clear instructions and commands to access Grafana dashboards, the custom UI, and ArgoCD UI after a successful CI run.
*   **Visual Monitoring with Grafana:** Integrated Grafana dashboards for both ArgoCD and Flux, allowing real-time monitoring of sync/suspend errors, reconciliation times, and overall system health.
*   **Custom UI for Manifest Comparison:** A simple web application built with React and Tailwind CSS that:
    *   Lists all applications managed by ArgoCD and Flux.
    *   Displays live Kubernetes manifests for each application.
    *   Highlights differences between the desired state (from Git) and the actual state in the cluster.

## 🏗️ Architecture Overview

This project sets up a Kubernetes cluster (KinD in CI, or Minikube/KinD locally) and deploys both ArgoCD and FluxCD. It then uses these GitOps tools to deploy sample Nginx applications, showcasing a fully Helm-based deployment strategy. A custom UI application is also deployed to provide a visual comparison interface.

## 📂 Project Structure

*   `main.tf`: Main Terraform configuration for deploying core GitOps tools and applications.
*   `modules/`: Terraform modules for installing ArgoCD and Flux.
*   `apps/`: Sample Nginx applications.
    *   `apps/argocd/helm-nginx/`: ArgoCD Application resource pointing to the Nginx Helm chart.
    *   `apps/flux/helm-nginx/`: FluxCD HelmRelease resource pointing to the Nginx Helm chart.
*   `charts/nginx/`: Reusable Helm chart for deploying Nginx applications.
*   `ui-backend/`: Node.js (Express.js) backend for the UI comparison tool.
*   `ui-frontend/`: React (Tailwind CSS) frontend for the UI comparison tool.
*   `kubernetes/ui/`: Kubernetes manifests for deploying the UI backend and frontend.
*   `.github/workflows/test-kind.yml`: The main GitHub Actions workflow for CI/CD.
*   `docs/`: Contains screenshots and other documentation.

## 🚀 Getting Started (Local Deployment)

To run this project locally, you'll need:

### Prerequisites

*   [Minikube](https://minikube.sigs.k8s.io/docs/start/) or [Kind](https://kind.sigs.k8s.io/docs/user/quick-start/) (for local Kubernetes cluster)
*   [Terraform](https://developer.hashicorp.com/terraform/downloads)
*   [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
*   [Flux CLI](https://fluxcd.io/flux/installation/)
*   [ArgoCD CLI](https://argo-cd.readthedocs.io/en/stable/cli_installation/) (optional, for local verification)
*   [Helm](https://helm.sh/docs/intro/install/)
*   [Docker](https://docs.docker.com/get-docker/) (for building and pushing UI images)

### Deployment Steps

1.  **Clone the repository:**

    ```bash
    git clone https://github.com/justrunme/gitops-duel-argocd-vs-flux.git
    cd gitops-duel-argocd-vs-flux
    ```

2.  **Start your Kubernetes cluster (e.g., Minikube):**

    ```bash
    minikube start
    ```

3.  **Initialize Terraform:**

    ```bash
    terraform init
    ```

4.  **Apply Terraform configurations to deploy ArgoCD, Flux, and Nginx applications:**

    ```bash
    terraform apply -auto-approve
    ```

5.  **Build and push UI Docker images (replace `justrunme` with your Docker Hub username):**

    ```bash
    docker build -t justrunme/gitops-duel-ui-backend:latest ./ui-backend
    docker push justrunme/gitops-duel-ui-backend:latest

    docker build -t justrunme/gitops-duel-ui-frontend:latest ./ui-frontend
    docker push justrunme/gitops-duel-ui-frontend:latest
    ```

6.  **Deploy the UI to Kubernetes:**

    ```bash
    kubectl apply -f kubernetes/ui/
    ```

### Accessing the Dashboards and UI

After successful deployment, you can access the various components:

*   **Grafana Dashboard:**
    1.  Get Grafana admin password:
        ```bash
        kubectl --namespace monitoring get secrets monitoring-grafana -o jsonpath="{.data.admin-password}" | base64 -d ; echo
        ```
    2.  Run port-forward in a separate terminal:
        ```bash
        kubectl --namespace monitoring port-forward svc/monitoring-grafana 3000:80
        ```
    3.  Open `http://localhost:3000` in your browser.
    4.  Login with username: `admin`, password: (output from step 1).

*   **Custom UI Dashboard:**
    1.  Run port-forward in a separate terminal:
        ```bash
        kubectl port-forward service/ui-frontend 8082:80 -n default
        ```
    2.  Open `http://localhost:8082` in your browser.

*   **ArgoCD UI:**
    1.  Run port-forward in a separate terminal:
        ```bash
        kubectl port-forward svc/argocd-server -n argocd 8080:80
        ```
    2.  Open `http://localhost:8080` in your browser.
    3.  Get initial admin password:
        ```bash
        kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
        ```

## 💡 GitOps Concepts

GitOps is an operational framework that applies DevOps best practices (like version control, collaboration, and CI/CD) to infrastructure automation. The Git repository becomes the single source of truth for your desired system state. Any changes to the system are made by updating the Git repository, and the GitOps tool (ArgoCD or FluxCD) automatically synchronizes the cluster to match this desired state.

### Pull-based vs. Push-based (Contextualized)

While both ArgoCD and Flux are "pull-based" in the sense that they pull configurations from Git, their internal mechanisms and typical deployment patterns can differ:

*   **ArgoCD (Pull-based):** ArgoCD agents run within the cluster and continuously monitor Git repositories for changes. When a change is detected, ArgoCD pulls the new configuration and applies it to the cluster. It has a strong focus on application lifecycle management and provides a rich UI.
*   **FluxCD (Pull-based with Event-driven Sync):** Flux also operates within the cluster, pulling configurations from Git. It's highly event-driven and can react to Git pushes or image updates. Flux's design emphasizes extensibility and composability, often integrating with other tools like Helm and Kustomize via custom resources (`HelmRelease`, `Kustomization`).

## ⚔️ ArgoCD vs FluxCD Comparison

| Feature             | ArgoCD                                       | FluxCD                                         |
| :------------------ | :------------------------------------------- | :--------------------------------------------- |
| **UI**              | Rich, built-in UI for visualization & management | CLI-centric, with optional UI (e.g., Weave GitOps, custom UI in this project) |
| **Sync Model**      | Pull-based, continuous reconciliation        | Pull-based, event-driven reconciliation        |
| **Application Definition** | `Application` CRD                            | `Kustomization` and `HelmRelease` CRDs         |
| **Helm Support**    | Excellent, native Helm chart support via `Application` CRD | Excellent, native `HelmRelease` CRD for managing Helm charts |
| **Self-Healing**    | Actively detects and corrects drift          | Actively detects and corrects drift            |
| **Extensibility**   | Plugins, custom resource support             | Highly extensible via GitOps Toolkit components |

## 💥 Error Simulation Scenarios

The CI pipeline includes automated error simulation to demonstrate the self-healing capabilities of ArgoCD and Flux:

*   **Deployment Deletion:** The CI pipeline intentionally deletes the Nginx deployments managed by both ArgoCD and Flux. The GitOps tools are expected to detect this drift and automatically re-deploy the applications to restore the desired state.
*   **Replica Count Modification:** The CI pipeline scales down the Nginx deployments to zero replicas. ArgoCD and Flux are expected to detect this change and scale the deployments back up to the desired replica count defined in Git.

Each simulation includes a waiting period for self-healing and verification steps to confirm that the desired state has been restored.

## 🔄 CI/CD Pipeline (`.github/workflows/test-kind.yml`)

The CI/CD pipeline is structured into several jobs to ensure a robust and comprehensive testing and deployment process:

1.  **`setup-kind`**: Initializes the KinD cluster and installs necessary CLI tools (Terraform, Flux, ArgoCD).
2.  **`deploy-core-components`**: Deploys ArgoCD and Flux into the KinD cluster using Terraform, including CRD readiness checks.
3.  **`deploy-nginx-apps`**: Applies Terraform configurations to deploy the Nginx applications via ArgoCD and Flux using their respective Helm integrations.
4.  **`build-and-deploy-ui`**: Builds Docker images for the custom UI backend and frontend, pushes them to Docker Hub, and deploys them to the KinD cluster.
5.  **`verify-deployments`**: Performs comprehensive checks to ensure all deployed components (Nginx applications, UI backend, UI frontend) are running and reachable.
6.  **`simulate-errors`**: Executes the error simulation scenarios to test self-healing.
7.  **`output-access-info`**: Provides detailed instructions and commands to access Grafana, the custom UI, and ArgoCD UI, including dynamic password retrieval for Grafana and ArgoCD.

## 🔍 Verification and Debugging Commands

Here are some useful commands for verifying deployments and debugging issues:

*   **ArgoCD:**
    ```bash
    argocd app list
    argocd app get <app-name>
    argocd app logs <app-name>
    ```
*   **FluxCD:**
    ```bash
    flux get all -A
    flux get kustomizations -A
    flux get helmreleases -A
    flux logs --kind=Kustomization --name=<kustomization-name> -n <namespace>
    flux logs --kind=HelmRelease --name=<helmrelease-name> -n <namespace>
    ```
*   **Kubernetes (General):**
    ```bash
    kubectl get pods -n default
    kubectl get deployments -n default
    kubectl get services -n default
    kubectl get pods -n flux-system
    kubectl get deployments -n flux-system
    kubectl get services -n flux-system
    kubectl get all -n argocd
    kubectl get all -n monitoring
    ```

## 📸 Screenshots

(Add screenshots here for ArgoCD UI, Flux UI (if any), Grafana Dashboards, and the custom UI comparison tool)