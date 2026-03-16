#!/bin/bash
# =============================================================================
# setup-k3s-local.sh
# eShopOnContainers – Local k3s Setup Script
# =============================================================================
# Tested on: Ubuntu 20.04 / 22.04, Debian 11/12
# Requirements: min. 8 GB RAM, 4 CPUs, 20 GB free disk
# Usage: chmod +x setup-k3s-local.sh && ./setup-k3s-local.sh
# =============================================================================

set -e  # Exit on any error

# --- Colors ------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Helpers -----------------------------------------------------------------
info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
success() { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- Config ------------------------------------------------------------------
NAMESPACE="eshop-local"
HOSTS_ENTRY="127.0.0.1  eshop.local"
ESHOP_DIR="./app"

# Determine repo root (script can be called from anywhere)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# =============================================================================
echo ""
echo "=============================================="
echo "  eShopOnContainers – Local k3s Setup"
echo "=============================================="
echo ""

# --- Check OS ----------------------------------------------------------------
if [[ "$OSTYPE" == "darwin"* ]]; then
  error "macOS detected. Please use Linux or WSL2 on Windows."
fi

# --- Check Resources ---------------------------------------------------------
info "Checking system resources..."

TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
if [ "$TOTAL_RAM" -lt 7 ]; then
  warn "Only ${TOTAL_RAM} GB RAM detected. Recommended: 8 GB minimum."
  warn "The deployment may be slow or unstable."
  read -p "Continue anyway? (y/N): " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || exit 0
else
  success "RAM: ${TOTAL_RAM} GB detected"
fi

CPU_CORES=$(nproc)
if [ "$CPU_CORES" -lt 4 ]; then
  warn "Only ${CPU_CORES} CPU cores detected. Recommended: 4 cores."
fi
success "CPUs: ${CPU_CORES} cores detected"

# --- Check Dependencies ------------------------------------------------------
info "Checking dependencies..."

for cmd in curl git; do
  if ! command -v $cmd &>/dev/null; then
    error "$cmd is not installed. Run: sudo apt install $cmd"
  fi
done
success "curl and git available"

# --- Install k3s -------------------------------------------------------------
if command -v k3s &>/dev/null; then
  success "k3s already installed: $(k3s --version | head -1)"
else
  info "Installing k3s..."
  curl -sfL https://get.k3s.io | sh -
  success "k3s installed"
fi

# --- Wait for k3s to be ready ------------------------------------------------
info "Waiting for k3s to be ready..."
sleep 5
for i in {1..30}; do
  if sudo k3s kubectl get nodes &>/dev/null; then
    success "k3s is running"
    break
  fi
  sleep 2
  if [ $i -eq 30 ]; then
    error "k3s did not start in time. Check: sudo systemctl status k3s"
  fi
done

# --- Configure kubeconfig ----------------------------------------------------
info "Configuring kubeconfig..."
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$USER:$USER" ~/.kube/config
export KUBECONFIG=~/.kube/config
success "kubeconfig configured at ~/.kube/config"

# --- Install kubectl (standalone, optional if k3s already provides it) -------
if ! command -v kubectl &>/dev/null; then
  info "Installing kubectl..."
  curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl
  sudo mv kubectl /usr/local/bin/kubectl
  success "kubectl installed"
else
  success "kubectl already available"
fi

# --- Install Helm -------------------------------------------------------------
if command -v helm &>/dev/null; then
  success "Helm already installed: $(helm version --short)"
else
  info "Installing Helm..."
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  success "Helm installed"
fi

# --- Init Git Submodule (app/) -----------------------------------------------
info "Initialising eShopOnContainers submodule..."

cd "$REPO_ROOT"

# Check if .gitmodules references the submodule
if [ ! -f ".gitmodules" ] || ! grep -q "app" .gitmodules; then
  error "No submodule 'app' found in .gitmodules.\n  Run first:\n    git submodule add https://github.com/dotnet-architecture/eShopOnContainers app\n    git commit -m 'chore: add eShopOnContainers submodule'\n    git push"
fi

# Init + update submodule if app/ is empty
if [ ! -f "app/.gitmodules" ] && [ -z "$(ls -A app 2>/dev/null)" ]; then
  git submodule update --init --recursive
  success "Submodule initialised"
else
  info "Submodule already present — pulling latest..."
  git submodule update --remote --merge
  success "Submodule up to date"
fi

cd - > /dev/null

# --- Create Namespace --------------------------------------------------------
info "Creating Kubernetes namespace: $NAMESPACE..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
success "Namespace '$NAMESPACE' ready"

# --- Deploy via Helm ---------------------------------------------------------
HELM_DIR="$REPO_ROOT/app/deploy/k8s/helm"
VALUES_LOCAL="$REPO_ROOT/kubernetes/helm/values-local.yaml"

if [ ! -d "$HELM_DIR" ]; then
  error "Helm charts not found at $HELM_DIR\n  Check that the submodule was initialised correctly."
fi

info "Deploying eShopOnContainers via Helm (this takes a few minutes)..."
cd "$HELM_DIR"

# Use local values override if it exists in your repo, otherwise use defaults
if [ -f "$VALUES_LOCAL" ]; then
  info "Using custom values-local.yaml..."
  ./deploy-all.sh --dns localhost --namespace "$NAMESPACE" \
    -f "$VALUES_LOCAL"
else
  info "No values-local.yaml found — using upstream defaults"
  ./deploy-all.sh --dns localhost --namespace "$NAMESPACE"
fi

cd - > /dev/null
success "Helm deployment triggered"

# --- /etc/hosts entry --------------------------------------------------------
if grep -q "eshop.local" /etc/hosts; then
  success "/etc/hosts entry already exists"
else
  info "Adding eshop.local to /etc/hosts..."
  echo "$HOSTS_ENTRY" | sudo tee -a /etc/hosts > /dev/null
  success "Added: $HOSTS_ENTRY"
fi

# --- Wait for pods -----------------------------------------------------------
info "Waiting for pods to start (this may take 3-5 minutes)..."
echo ""
echo "  You can monitor progress in another terminal with:"
echo "  kubectl get pods -n $NAMESPACE -w"
echo ""

# Wait for at least the catalog pod to be running as a proxy for readiness
for i in {1..60}; do
  RUNNING=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null \
    | grep -c "Running" || true)
  TOTAL=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null \
    | wc -l || true)
  echo -ne "\r  Pods running: ${RUNNING}/${TOTAL} ..."
  if [ "$RUNNING" -ge 10 ]; then
    echo ""
    success "Core pods are running"
    break
  fi
  sleep 5
  if [ $i -eq 60 ]; then
    echo ""
    warn "Not all pods started yet — check with: kubectl get pods -n $NAMESPACE"
  fi
done

# --- Summary -----------------------------------------------------------------
echo ""
echo "=============================================="
echo -e "${GREEN}  Setup complete!${NC}"
echo "=============================================="
echo ""
echo "  🌐 Web MVC App:     http://eshop.local"
echo "  📊 Health Status:   http://eshop.local/status"
echo "  📦 Catalog API:     http://eshop.local/catalog-api"
echo ""
echo "  🔑 Demo Login:"
echo "     Email:    demouser@microsoft.com"
echo "     Password: Pass@word1"
echo ""
echo "  🔧 Useful commands:"
echo "     kubectl get pods -n $NAMESPACE"
echo "     kubectl get pods -n $NAMESPACE -w        # watch"
echo "     kubectl logs -n $NAMESPACE <pod-name>"
echo "     kubectl describe pod -n $NAMESPACE <pod-name>"
echo ""
echo "  🗑️  Uninstall k3s:  /usr/local/bin/k3s-uninstall.sh"
echo "=============================================="
echo ""
