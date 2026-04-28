# eShopOnContainers DevOps Project

**JAN26-Group6**

> A production-ready DevOps implementation of the eShopOnContainers microservices ecommerce platform, featuring full CI/CD automation, Kubernetes orchestration, infrastructure as code, monitoring, and security scanning.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture Diagram](#architecture-diagram)
3. [Tech Stack](#tech-stack)
4. [Application Components](#application-components)
5. [Infrastructure](#infrastructure)
6. [Setup Steps](#setup-steps)
7. [How to Deploy Dev & Prod](#how-to-deploy-dev--prod)
8. [CI/CD Pipeline](#cicd-pipeline)
9. [Monitoring](#monitoring)
10. [Security](#security)
11. [Disaster Recovery](#disaster-recovery)

---

## Overview

eShopOnContainers is a microservices-based ecommerce application built with .NET 7. It simulates a real-world online shop with separate services for catalog browsing, basket management, order processing, identity/authentication, and payment handling.

This project wraps the application in a full DevOps lifecycle:

- Infrastructure provisioned automatically with **Terraform** on **Proxmox**
- Application containerized with **Docker** and stored in a **GitLab Container Registry**
- Deployed to **k3s Kubernetes** clusters using **Helm charts**
- Three isolated environments: **dev**, **staging**, and **prod**
- Fully automated **GitLab CI/CD pipeline** with manual approval gate for production
- **Prometheus + Grafana** monitoring stack with live metrics from all microservices
- **Trivy** security scanning for dependencies and Docker images
- **HTTPS** via Certbot SSL certificates on all public endpoints

---

## Architecture Diagram

```
                        Internet
                           │
                    62.210.88.216
                    (Public IP)
                           │
                     Nginx Reverse Proxy
                     (SSL/TLS Certbot)
                           │
          ┌────────────────┼────────────────┐
          │                │                │
    dev.domain       staging.domain    prod.domain
          │                │                │
   10.10.20.10       10.10.30.10      10.10.40.10
   k3s-dev VM        k3s-staging VM   k3s-prod VM
          │
   ┌──────┴──────────────────────────────┐
   │           Traefik Ingress           │
   └──────┬──────────────────────────────┘
          │
   ┌──────┴─────────────────────────────────────────┐
   │              eshop-dev namespace               │
   │                                                │
   │  ┌─────────┐  ┌─────────┐  ┌──────────────┐    │
   │  │Basket   │  │Catalog  │  │  Identity    │    │
   │  │  API    │  │  API    │  │    API       │    │
   │  └────┬────┘  └────┬────┘  └──────┬───────┘    │
   │       │            │              │            │
   │  ┌────┴────┐  ┌────┴────┐  ┌─────┴──────┐      │
   │  │Ordering │  │Payment  │  │  Webhooks  │      │
   │  │  API    │  │  API    │  │    API     │      │
   │  └────┬────┘  └─────────┘  └────────────┘      │
   │       │                                        │
   │  ┌────┴──────────────────────────────────┐     │
   │  │           RabbitMQ (Event Bus)        │     │
   │  └───────────────────────────────────────┘     │
   │                                                │
   │  ┌────────────┐  ┌───────┐  ┌─────────────┐    │
   │  │ SQL Server │  │ Redis │  │  MongoDB    │    │
   │  └────────────┘  └───────┘  └─────────────┘    │
   └────────────────────────────────────────────────┘

   ┌─────────────────────────────────────┐
   │         monitoring namespace        │
   │  ┌──────────────┐  ┌─────────────┐  │
   │  │  Prometheus  │  │   Grafana   │  │
   │  └──────────────┘  └─────────────┘  │
   └─────────────────────────────────────┘

   ┌─────────────────────────────────────┐
   │         GitLab CE (10.10.10.10)     │
   │  ┌──────────────────────────────┐   │
   │  │     GitLab Runner VM         │   │
   │  │  (vm102-docker-runner)       │   │
   │  └──────────────────────────────┘   │
   └─────────────────────────────────────┘
```

## CI/CD Pipeline

The pipeline is defined in `.gitlab-ci.yml` and consists of 5 stages:

### Stage 1: test

Runs on every push. Executes unit tests and dependency scanning in parallel.

```
unit-tests        → dotnet test for EventBus, Basket, Catalog, Ordering
dependency-scan   → Trivy filesystem scan for vulnerable packages
```

### Stage 2: build

Runs only on `dev` branch when `src/` files change. Builds and pushes 14 Docker images in parallel using a matrix strategy.

```
build-and-push → docker build + push for all 14 services
```

Each image is tagged with:
- `linux-latest` — always points to the most recent build
- `linux-{commit-sha}` — immutable tag for traceability

### Stage 3: deploy

Deploys infrastructure services (SQL, Redis, RabbitMQ) then application services via Helm.

```
deploy-dev      → automatic on dev branch  → k3s-dev
deploy-staging  → automatic on main branch → k3s-staging
```

### Stage 4: promote

```
deploy-prod → MANUAL APPROVAL → k3s-prod
```

### Stage 5: monitoring

Deploys or upgrades the `kube-prometheus-stack` Helm chart and applies the `ServiceMonitor` for scraping app metrics.

```
deploy-monitoring-dev     → after deploy-dev
deploy-monitoring-staging → after deploy-staging (commented out)
deploy-monitoring-prod    → manual, after deploy-prod (commented out)
```

### Branching Strategy

```
main   → staging + prod (prod requires manual approval)
dev    → dev environment (fully automatic)
```

Feature branches should be merged into `dev` for testing, then `dev` merged into `main` for staging/production promotion.

### CI/CD Pipeline Flow

```
 Git Push (dev branch)
        │
        ▼
 ┌─────────────┐
 │  Stage 1    │  Unit Tests (dotnet test)
 │    test     │
 │  dep-scan   │  Trivy dependency scan
 └──────┬──────┘
        │
        ▼
 ┌─────────────┐
 │  Stage 2    │  Docker build + push to GitLab Registry
 │    build    │  (14 service images)
 └──────┬──────┘
        │
        ▼
 ┌─────────────┐
 │  Stage 3    │  Helm deploy to k3s-dev (automatic)
 │   deploy    │  Helm deploy to k3s-staging (on main branch)
 └──────┬──────┘
        │
        ▼
 ┌─────────────┐
 │  Stage 4    │  Deploy to k3s-prod (MANUAL APPROVAL)
 │   promote   │
 └──────┬──────┘
        │
        ▼
 ┌─────────────┐
 │  Stage 5    │  Deploy Prometheus + Grafana
 │ monitoring  │  Apply ServiceMonitor
 │             │  Restart app pods
 └─────────────┘
```

---

## Tech Stack

| Category | Technology |
|---|---|
| Application | .NET 7, ASP.NET Core Web API |
| Containerization | Docker, multi-stage Dockerfiles |
| Container Registry | GitLab Container Registry |
| Orchestration | k3s Kubernetes |
| Package Manager | Helm 3 |
| CI/CD | GitLab CE CI/CD |
| Infrastructure as Code | Terraform |
| Virtualization | Proxmox VE |
| Message Broker | RabbitMQ |
| Databases | SQL Server, Redis |
| Monitoring | Prometheus, Grafana (kube-prometheus-stack) |
| Security Scanning | Trivy |
| Reverse Proxy | Nginx |
| SSL/TLS | Certbot (Let's Encrypt) |
| Ingress Controller | Traefik (k3s built-in) |
| Secrets Management | GitLab CI/CD Variables, Kubernetes Secrets |

---

## Application Components

The application consists of 14 microservices:

| Service | Description | Port |
|---|---|---|
| **Basket API** | Shopping cart management, backed by Redis | 80, 81 (gRPC) |
| **Catalog API** | Product catalog with images, backed by SQL Server | 80, 81 (gRPC) |
| **Identity API** | Authentication and authorization (IdentityServer4) | 80 |
| **Ordering API** | Order processing and management | 80, 81 (gRPC) |
| **Ordering Background Tasks** | Async order processing jobs | 80 |
| **Ordering SignalR Hub** | Real-time order status updates | 80 |
| **Payment API** | Payment processing simulation | 80 |
| **Webhooks API** | Webhook subscriptions and notifications | 80 |
| **Webhooks Client** | Test client for webhooks | 80 |
| **WebMVC** | Server-side rendered web frontend | 80 |
| **WebSPA** | Angular single-page application frontend | 80 |
| **WebStatus** | Health check dashboard for all services | 80 |
| **Mobile Shopping Aggregator** | BFF aggregator for mobile clients | 80 |
| **Web Shopping Aggregator** | BFF aggregator for web clients | 80 |

### Supporting Infrastructure Services

| Service | Purpose |
|---|---|
| **RabbitMQ** | Event bus for inter-service communication |
| **SQL Server** | Persistent relational storage (Catalog, Ordering, Identity, Webhooks) |
| **Redis (Basket Data)** | Shopping cart session storage |
| **Redis (Keystore)** | Distributed cache and data protection keys |

---

## Infrastructure

### Proxmox Virtual Machines

| VM | IP | Role |
|---|---|---|
| gitlab-ce | 10.10.10.10 | GitLab CE server + Container Registry |
| gitlab-runner | 10.10.10.x | GitLab CI/CD runner (Docker executor) |
| k3s-dev | 10.10.20.10 | Development Kubernetes cluster |
| k3s-staging | 10.10.30.10 | Staging Kubernetes cluster |
| k3s-prod | 10.10.40.10 | Production Kubernetes cluster |

### Terraform

Infrastructure is provisioned using Terraform with the Proxmox provider. The Terraform configuration is located in the `terraform/` directory.

To provision infrastructure from scratch:

```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

This creates all 5 VMs with the correct network configuration, CPU, and memory allocations.

### Kubernetes Namespaces

| Namespace | Purpose |
|---|---|
| `eshop-dev` | Development environment workloads |
| `eshop-staging` | Staging environment workloads |
| `eshop-prod` | Production environment workloads |
| `monitoring` | Prometheus + Grafana stack |
| `kube-system` | Traefik ingress controller |

---

## Setup Steps

### Prerequisites

- Proxmox VE host with sufficient resources
- Domain name with wildcard DNS pointing to public IP
- GitLab CE instance running
- kubectl installed locally
- Helm 3 installed locally
- Terraform installed locally

### 1. Provision Infrastructure

```bash
cd terraform/
terraform init
terraform apply
```

### 2. Configure GitLab CI/CD Variables

In GitLab → Settings → CI/CD → Variables, add:

| Variable | Description | Masked |
|---|---|---|
| `DEPLOY_TOKEN_USER` | GitLab registry deploy token username | Yes |
| `DEPLOY_TOKEN_PASSWORD` | GitLab registry deploy token password | Yes |
| `GRAFANA_PASSWORD` | Grafana admin password | Yes |

### 3. Configure Kubernetes Access

On each k3s VM, the kubeconfig is at `/etc/rancher/k3s/k3s.yaml`. The GitLab runner uses pre-configured kubeconfig files at:

```
/root/.kube/k3s-dev.yaml
/root/.kube/k3s-staging.yaml
/root/.kube/k3s-prod.yaml
```

### 4. Deploy

Push to the `dev` branch to trigger the pipeline:

```bash
git checkout dev
git push origin dev
```

The pipeline will automatically:
- Run unit tests and dependency scanning
- Build and push all Docker images
- Deploy to k3s-dev
- Deploy Prometheus + Grafana monitoring

---

## How to Deploy Dev & Prod

### Environment Differences

| Configuration | Dev | Staging | Prod |
|---|---|---|---|
| Kubernetes cluster | k3s-dev (10.10.20.10) | k3s-staging (10.10.30.10) | k3s-prod (10.10.40.10) |
| Namespace | eshop-dev | eshop-staging | eshop-prod |
| Domain | dev.jan26-group6-eshoponcontainers.abrdns.com | staging.jan26-group6-eshoponcontainers.abrdns.com | jan26-group6-eshoponcontainers.abrdns.com |
| Deployment trigger | Automatic on `dev` branch push | Automatic on `main` branch push | Manual approval required |
| Prometheus retention | 3d | 7d | 15d |
| Prometheus storage | 2Gi | 5Gi | 10Gi |

### Deploy to Dev

```bash
git checkout dev
git push origin dev
# Pipeline runs automatically
```

### Deploy to Staging

```bash
git checkout main
git merge dev
git push origin main
# Pipeline runs automatically
```

### Deploy to Production

1. Push to `main` branch (deploys staging automatically)
2. In GitLab → CI/CD → Pipelines → find the pipeline
3. Click the **play button** on the `deploy-prod` job
4. Confirm manual deployment

### Rollback a Deployment

To roll back to the previous version:

```bash
# Roll back a specific service
helm rollback eshop-basket-api 0 -n eshop-prod

# Roll back all services to previous revision
for chart in basket-api catalog-api identity-api ordering-api payment-api; do
  helm rollback eshop-$chart 0 -n eshop-prod
done
```

The `0` means "previous revision". Use `helm history eshop-basket-api -n eshop-prod` to see all revisions.

---

## Monitoring

### Stack

The monitoring stack uses `kube-prometheus-stack` Helm chart which bundles:
- **Prometheus** — time-series metrics storage and querying
- **Grafana** — dashboards and visualization
- **kube-state-metrics** — Kubernetes object metrics
- **node-exporter** — VM-level CPU/memory/disk metrics
- **Prometheus Operator** — manages Prometheus configuration via CRDs

### How Metrics are Collected

Each .NET service exposes a `/metrics` endpoint powered by `prometheus-net.AspNetCore`. The endpoint is added via `MonitoringExtensions.cs` in the shared `WebHost.Customization` library:

```csharp
// In each service's Startup.cs
services.AddPrometheusMonitoring();   // ConfigureServices
app.UsePrometheusMonitoring();        // Configure - after UseRouting
endpoints.MapPrometheusMonitoring();  // Configure - inside UseEndpoints
```

A `ServiceMonitor` Kubernetes CRD tells Prometheus which services to scrape:

```yaml
# kubernetes/monitoring/servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: eshop-services
  namespace: monitoring
spec:
  namespaceSelector:
    matchNames:
      - eshop-dev
  selector:
    matchLabels:
      monitor: "true"
  endpoints:
    - port: http
      path: /metrics
      interval: 15s
```

Services are labeled `monitor: "true"` via `kubectl label` in the deploy stage.

### Accessing Grafana

Grafana is available at:

```
https://grafana.dev.jan26-group6-eshoponcontainers.abrdns.com
```

- Username: `admin`
- Password: stored in `GRAFANA_PASSWORD` GitLab CI/CD variable

The **ASP.NET Core dashboard** (Grafana ID: 10427) is auto-imported and shows:
- HTTP request rate per endpoint
- Response time percentiles (p50, p95, p99)
- Error rates by status code
- In-flight requests

### Prometheus Queries

Useful PromQL queries for the eShop:

```promql
# Request rate per service (last 5 minutes)
rate(http_requests_received_total[5m])

# 99th percentile response time
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))

# Error rate (5xx responses)
rate(http_requests_received_total{code=~"5.."}[5m])

# Currently in-flight requests
http_requests_in_progress
```

---

## Security

### Secrets Management

All sensitive values are stored as **GitLab CI/CD Variables** (masked and protected). They are injected as environment variables at pipeline runtime and never appear in code or logs.

| Secret | Storage Location | Usage |
|---|---|---|
| Registry credentials | GitLab CI/CD Variables | Docker image push/pull |
| Grafana admin password | GitLab CI/CD Variables | Grafana Helm deployment |
| Kubernetes registry secret | Kubernetes Secret (`eshop-registry-secret`) | Pod image pull authentication |

### HTTPS / TLS

All public endpoints are served over HTTPS via:
- **Certbot (Let's Encrypt)** SSL certificates on the Nginx reverse proxy
- Certificates auto-renew via Certbot's systemd timer
- HTTP requests are automatically redirected to HTTPS (301 redirect)

### Dependency Scanning (Trivy)

Every pipeline run scans the source code for vulnerable NuGet and npm packages using **Trivy**:

```yaml
trivy fs ./src \
  --scanners vuln \
  --severity HIGH,CRITICAL \
  --format table
```

Results are saved as a JSON artifact (`trivy-dependency-report.json`) downloadable from every pipeline run.

### Docker Image Scanning (Trivy)

After Docker images are built, Trivy scans each image for OS-level and library vulnerabilities:

```yaml
trivy image \
  --severity HIGH,CRITICAL \
  $REGISTRY_IMAGE/$service:linux-latest
```

### No Hard-coded Secrets

The codebase and pipeline configuration contain zero hard-coded credentials. All secrets flow through GitLab CI/CD Variables → environment variables → Kubernetes Secrets.

---

## Disaster Recovery

### Container/Pod Failure

Kubernetes handles pod failures automatically:

- **Restart policy** — all deployments use `restartPolicy: Always`. If a container crashes, Kubernetes restarts it automatically
- **Health checks** — all services expose `/liveness` and `/hc` endpoints. Kubernetes restarts pods that fail liveness checks
- **Self-healing** — if a pod is deleted, the Deployment controller immediately creates a replacement

To manually verify recovery:
```bash
# Delete a pod — Kubernetes will recreate it automatically
kubectl delete pod eshop-basket-api-xxx -n eshop-dev
kubectl get pods -n eshop-dev -w  # watch it come back
```

### Node Failure

If the k3s VM itself fails:

1. The Proxmox host keeps the VM configuration
2. Restart the VM from Proxmox console
3. k3s starts automatically on boot
4. All pods are rescheduled automatically (single-node cluster — no rescheduling needed)

### Redeploy Infrastructure from IaC

If a VM needs to be rebuilt from scratch:

```bash
cd terraform/

# Destroy and recreate a specific VM
terraform destroy -target=proxmox_vm_qemu.k3s-dev
terraform apply -target=proxmox_vm_qemu.k3s-dev
```

Then re-run the pipeline — it will redeploy all Helm charts and the monitoring stack automatically.

### Rollback to Previous Version

**Application rollback** via Helm:
```bash
# See revision history
helm history eshop-basket-api -n eshop-prod

# Roll back to previous revision
helm rollback eshop-basket-api 0 -n eshop-prod
```

**Full environment rollback** — re-run a previous pipeline in GitLab:
1. Go to GitLab → CI/CD → Pipelines
2. Find the last known-good pipeline
3. Click **Retry** — it redeploys all services from the images built at that commit

### Database Backup Strategy

SQL Server and Redis data is stored on Kubernetes PersistentVolumes backed by local storage on the k3s VMs.

**SQL Server backup:**
```bash
# Run a backup job inside the SQL Server pod
kubectl exec -n eshop-dev eshop-sql-data-xxx -- \
  /opt/mssql-tools/bin/sqlcmd -S localhost \
  -U sa -P $SA_PASSWORD \
  -Q "BACKUP DATABASE [CatalogDb] TO DISK='/var/opt/mssql/backup/catalog.bak'"
```

**Redis backup:**
Redis is used for session storage (basket, keystore). Data is ephemeral by design — if Redis is lost, users lose their shopping cart session but no permanent data is affected.

**Recovery time objective (RTO):** ~5 minutes for pod failures, ~15 minutes for full VM rebuild via Terraform + pipeline rerun.

---

## Project URLs

| Environment | URL |
|---|---|
| Development | https://dev.jan26-group6-eshoponcontainers.abrdns.com |
| Staging | https://staging.jan26-group6-eshoponcontainers.abrdns.com |
| Production | https://jan26-group6-eshoponcontainers.abrdns.com |
| Grafana (Dev) | https://grafana.dev.jan26-group6-eshoponcontainers.abrdns.com |
| GitLab | https://gitlab.jan26-group6-eshoponcontainers.abrdns.com |

---

*Group 6 — January 2026 DevOps Cohort*
