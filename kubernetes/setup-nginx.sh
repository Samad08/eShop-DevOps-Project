#!/usr/bin/env bash
# setup-nginx.sh — Install nginx ingress controller and configure it for eShopOnContainers.
# Run this once before deploying with deploy-all.ps1.
#
# Usage: bash kubernetes/setup-nginx.sh

set -e

echo "==> Installing nginx ingress controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml

echo "==> Waiting for nginx controller to be ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

echo "==> Patching nginx ConfigMap for large cookies (ASP.NET Core auth)..."
kubectl patch configmap ingress-nginx-controller -n ingress-nginx --patch \
  '{"data":{"large-client-header-buffers":"4 32k","proxy-buffer-size":"32k","proxy-buffers":"4 32k"}}'

echo "==> Restarting nginx controller to apply config..."
kubectl rollout restart deployment ingress-nginx-controller -n ingress-nginx

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=60s

echo ""
echo "nginx ingress controller is ready."
echo "Next: run kubernetes/deploy-all.ps1 to deploy eShopOnContainers."
