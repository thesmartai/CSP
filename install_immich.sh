#!/usr/bin/env bash
set -Eeuo pipefail

########################################
# Konfiguration (bei Bedarf anpassen)
########################################
K8S_OBJECT_DIR="${K8S_OBJECT_DIR:-/home/ubuntu/k8s-objects}"

IMMICH_NS="${IMMICH_NS:-immich}"
CNPG_NS="${CNPG_NS:-cnpg-system}"
CONTOUR_NS="${CONTOUR_NS:-projectcontour}"

# Immich
IMMICH_RELEASE="${IMMICH_RELEASE:-immich}"
IMMICH_CHART="oci://ghcr.io/immich-app/immich-charts/immich"
IMMICH_CHART_VERSION="${IMMICH_CHART_VERSION:-0.10.3}"   # immich-charts Release (Nov 2025)
IMMICH_IMAGE_TAG="${IMMICH_IMAGE_TAG:-v2.4.0}"            # Immich App Version (Beispiel)

# CloudNativePG
CNPG_RELEASE="${CNPG_RELEASE:-cnpg}"
CNPG_REPO_NAME="${CNPG_REPO_NAME:-cnpg}"
CNPG_REPO_URL="${CNPG_REPO_URL:-https://cloudnative-pg.github.io/charts}"
CNPG_CHART="${CNPG_REPO_NAME}/cloudnative-pg"
CNPG_CHART_VERSION="${CNPG_CHART_VERSION:-0.27.0}"        # Beispiel von ArtifactHub

# Contour
CONTOUR_RELEASE="${CONTOUR_RELEASE:-contour}"
CONTOUR_REPO_NAME="${CONTOUR_REPO_NAME:-contour}"
CONTOUR_REPO_URL="${CONTOUR_REPO_URL:-https://projectcontour.github.io/helm-charts/}"
CONTOUR_CHART="${CONTOUR_REPO_NAME}/contour"
# (Optional pinnen; leer lassen => latest)
CONTOUR_CHART_VERSION="${CONTOUR_CHART_VERSION:-}"

# DB Secret
DB_SECRET_NAME="${DB_SECRET_NAME:-immich-db-app}"
DB_USERNAME="${DB_USERNAME:-immich}"
DB_PASSWORD_FILE="${DB_PASSWORD_FILE:-./immich-db-password.txt}"  # wird lokal erzeugt, falls neu generiert

########################################
# Helpers
########################################
log() { printf "\n[%s] %s\n" "$(date -Is)" "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Command fehlt: $1"
}

retry() { # retry <tries> <sleepSeconds> <cmd...>
  local tries="$1"; shift
  local sleep_s="$1"; shift
  local n=1
  until "$@"; do
    if (( n >= tries )); then return 1; fi
    log "Retry ($n/$tries): $*"
    n=$((n+1))
    sleep "$sleep_s"
  done
}

on_err() {
  echo
  echo "❌ Abbruch in Zeile $1. Letzte Aktion fehlgeschlagen."
}
trap 'on_err $LINENO' ERR

########################################
# Preflight
########################################
need_cmd sudo
need_cmd bash
need_cmd curl

# kubectl (RKE2)
export PATH="$PATH:/var/lib/rancher/rke2/bin"
need_cmd kubectl

log "Warte auf rke2-server & kubeconfig..."
retry 60 5 sudo systemctl is-active --quiet rke2-server
retry 60 5 sudo test -f /etc/rancher/rke2/rke2.yaml

# kubeconfig sicher ins Home kopieren
log "Setze kubeconfig sicher in ~/.kube/config (chmod 600)"
install -d -m 700 "$HOME/.kube"
sudo cp /etc/rancher/rke2/rke2.yaml "$HOME/.kube/config"
sudo chown "$USER:$USER" "$HOME/.kube/config"
chmod 600 "$HOME/.kube/config"
export KUBECONFIG="$HOME/.kube/config"

log "Warte auf Kubernetes API..."
retry 36 5 kubectl get nodes >/dev/null 2>&1

########################################
# Namespace(s)
########################################
log "Namespaces anlegen (idempotent)"
kubectl get ns "$IMMICH_NS" >/dev/null 2>&1 || kubectl create ns "$IMMICH_NS"
kubectl get ns "$CNPG_NS"   >/dev/null 2>&1 || kubectl create ns "$CNPG_NS"
kubectl get ns "$CONTOUR_NS" >/dev/null 2>&1 || kubectl create ns "$CONTOUR_NS"

########################################
# Helm installieren (falls fehlt)
########################################
if ! command -v helm >/dev/null 2>&1; then
  log "Helm nicht gefunden -> installiere via offizielles Script"
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi
need_cmd helm

########################################
# Storage / PVC
########################################
log "PVC anwenden: ${K8S_OBJECT_DIR}/persistentVolumeClaim.yaml"
kubectl apply -n "$IMMICH_NS" -f "${K8S_OBJECT_DIR}/persistentVolumeClaim.yaml"

########################################
# DB Secret (automatisch, ohne hartcodiertes Passwort)
########################################
log "DB Secret prüfen/anlegen: ${DB_SECRET_NAME}"
if kubectl -n "$IMMICH_NS" get secret "$DB_SECRET_NAME" >/dev/null 2>&1; then
  log "DB Secret existiert bereits -> lasse es unverändert"
else
  if [[ -n "${DB_PASSWORD:-}" ]]; then
    log "Nutze DB_PASSWORD aus ENV (nicht gespeichert)"
    PASS="$DB_PASSWORD"
  else
    log "Generiere zufälliges DB Passwort und schreibe es nach ${DB_PASSWORD_FILE} (chmod 600)"
    PASS="$(openssl rand -base64 32)"
    (umask 077 && printf "%s\n" "$PASS" > "$DB_PASSWORD_FILE")
  fi

  kubectl -n "$IMMICH_NS" create secret generic "$DB_SECRET_NAME" \
    --from-literal=username="$DB_USERNAME" \
    --from-literal=password="$PASS" \
    --dry-run=client -o yaml | kubectl apply -f -
fi

########################################
# CloudNativePG Operator
########################################
log "Installiere/Update CloudNativePG Operator (Helm, wait+atomic)"
helm repo add "$CNPG_REPO_NAME" "$CNPG_REPO_URL" >/dev/null 2>&1 || true
helm repo update >/dev/null

helm upgrade --install "$CNPG_RELEASE" "$CNPG_CHART" \
  --namespace "$CNPG_NS" --create-namespace \
  --version "$CNPG_CHART_VERSION" \
  --wait --timeout 10m --atomic

log "CNPG Cluster manifest anwenden: ${K8S_OBJECT_DIR}/cloudnative-pg.yaml"
kubectl apply -n "$IMMICH_NS" -f "${K8S_OBJECT_DIR}/cloudnative-pg.yaml"

log "Warte bis Postgres Cluster ready ist..."
kubectl wait -n "$IMMICH_NS" --for=condition=Ready "cluster/immich-database" --timeout=15m

########################################
# Contour Ingress Controller (Helm)
########################################
log "Installiere/Update Contour (Helm, wait+atomic)"
helm repo add "$CONTOUR_REPO_NAME" "$CONTOUR_REPO_URL" >/dev/null 2>&1 || true
helm repo update >/dev/null

CONTOUR_VERSION_ARGS=()
if [[ -n "$CONTOUR_CHART_VERSION" ]]; then
  CONTOUR_VERSION_ARGS+=(--version "$CONTOUR_CHART_VERSION")
fi

helm upgrade --install "$CONTOUR_RELEASE" "$CONTOUR_CHART" \
  --namespace "$CONTOUR_NS" --create-namespace \
  "${CONTOUR_VERSION_ARGS[@]}" \
  --wait --timeout 10m --atomic

########################################
# Immich (Valkey integriert)
########################################
log "Installiere/Update Immich (Helm, wait+atomic)"
helm upgrade --install "$IMMICH_RELEASE" "$IMMICH_CHART" \
  --namespace "$IMMICH_NS" --create-namespace \
  --version "$IMMICH_CHART_VERSION" \
  --values "${K8S_OBJECT_DIR}/values.yaml" \
  --set "image.tag=${IMMICH_IMAGE_TAG}" \
  --wait --timeout 20m --atomic

########################################
# Ingress
########################################
log "Ingress anwenden: ${K8S_OBJECT_DIR}/ingress.yaml"
# Wichtig bei Contour per Helm: ingressClassName: contour verwenden. :contentReference[oaicite:1]{index=1}
kubectl apply -n "$IMMICH_NS" -f "${K8S_OBJECT_DIR}/ingress.yaml"

########################################
# Status / Endpoint
########################################
log "Status"
kubectl get nodes
kubectl get pods -n "$IMMICH_NS" -o wide
kubectl get svc  -n "$IMMICH_NS"
kubectl get ingress -n "$IMMICH_NS" || true
kubectl get pods -n "$CONTOUR_NS" -o wide

# LB-IP/Hostname vom Envoy-Service finden (Label basiert, unabhängig vom Release-Namen)
LB_ADDR="$(kubectl -n "$CONTOUR_NS" get svc -l app.kubernetes.io/component=envoy -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
if [[ -z "$LB_ADDR" ]]; then
  LB_ADDR="$(kubectl -n "$CONTOUR_NS" get svc -l app.kubernetes.io/component=envoy -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
fi

log "✅ Fertig. Contour LB Address: ${LB_ADDR:-<noch keine (pending)>}"
