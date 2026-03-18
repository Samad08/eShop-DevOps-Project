# eshopOnContainers-devops
DevOps project – eShopOnContainers on Proxmox with Kubernetes, CI/CD, Monitoring

---

## Local Setup

### Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) with Kubernetes enabled
- [Helm v3](https://helm.sh/docs/intro/install/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

---

### Option 1 — Docker Compose

```bash
# 1. Copy and configure the environment file
cp src/.env.example src/.env
# Edit src/.env and set ESHOP_EXTERNAL_DNS_NAME_OR_IP:
#   Windows: host.docker.internal
#   Mac:     docker.for.mac.localhost
#   Linux:   your machine's LAN IP (e.g. 192.168.1.100)

# 2. Start all containers
cd src
docker compose up -d
```

**URLs:**

| Service | URL |
|---|---|
| MVC Web App | http://host.docker.internal:5100 |
| SPA Web App | http://host.docker.internal:5104 |
| Identity / Auth | http://host.docker.internal:5105 |
| Web Status | http://host.docker.internal:5107 |

> **Note:** Always access via the hostname you set in `.env`, not `localhost`.
> Demo login: `demouser@microsoft.com` / `Pass@word1`

---

### Option 2 — Kubernetes (Docker Desktop)

**Step 1 — Enable Kubernetes in Docker Desktop**

Settings → Kubernetes → Enable Kubernetes → Apply & Restart

**Step 2 — Install and configure nginx ingress (once)**

```bash
bash kubernetes/setup-nginx.sh
```

**Step 3 — Deploy eShopOnContainers**

```powershell
cd kubernetes/helm
./deploy-all.ps1 -externalDns host.docker.internal -imageTag linux-latest -imagePullPolicy IfNotPresent -clean $false
```

**Step 4 — Wait for all pods to be ready**

```bash
kubectl get pods -n default --watch
```

All pods should show `1/1 Running`.

**URLs:**

| Service | URL |
|---|---|
| MVC Web App | http://host.docker.internal/webmvc |
| SPA Web App | http://host.docker.internal/ |
| Identity / Auth | http://host.docker.internal/identity |
| Web Status | http://host.docker.internal/webstatus |
| Webhooks Client | http://host.docker.internal/webhooks-web |

> **Note:** If login fails after a redeployment, clear cookies for `host.docker.internal` in your browser (or use an Incognito window). This happens because ASP.NET Core Data Protection keys change between pod restarts.

---

## Repository Structure

```
eshopOnContainers-devops/
├── src/                  # Application source code
│   ├── .env.example      # Environment config template
│   └── docker-compose.yml
├── kubernetes/
│   ├── helm/             # Helm charts for all services
│   ├── setup-nginx.sh    # nginx ingress setup script (run once)
│   └── deploy-all.ps1    # Helm deploy script
├── terraform/            # IaC for Proxmox VM + k3s (Phase 3)
└── docs/                 # Architecture diagrams and documentation
```
