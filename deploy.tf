###########################################################
# deploy.tf (OPTIMAL)
###########################################################

variable "deploy_apps" {
  type    = bool
  default = true
}

resource "null_resource" "deploy_k8s_stack" {
  count      = var.deploy_apps ? 1 : 0
  depends_on = [module.rke2]

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = var.ssh_private_key
    host        = module.rke2.external_ip
    timeout     = "5m"
  }

  # Zielordner sicher anlegen
  provisioner "remote-exec" {
    inline = [
      "set -euo pipefail",
      "mkdir -p /home/ubuntu/k8s-objects"
    ]
  }

  provisioner "file" {
    source      = "${path.module}/kubernetes-objects/"
    destination = "/home/ubuntu/k8s-objects/"
  }

  provisioner "remote-exec" {
    inline = [
      "set -euo pipefail",

      "echo '--- Warte auf rke2-server & kubeconfig (max ~5min) ---'",
      "for i in $(seq 1 60); do sudo systemctl is-active --quiet rke2-server && break; echo \"rke2-server noch nicht aktiv ($i/60)\"; sleep 5; done",
      "for i in $(seq 1 60); do sudo test -f /etc/rancher/rke2/rke2.yaml && break; echo \"rke2.yaml noch nicht da ($i/60)\"; sleep 5; done",

      "export PATH=$PATH:/var/lib/rancher/rke2/bin",
      "export KUBECONFIG=/etc/rancher/rke2/rke2.yaml",
      "sudo chmod 644 /etc/rancher/rke2/rke2.yaml",

      "echo '--- Warte kurz auf Kubernetes API (max ~3min) ---'",
      "for i in $(seq 1 36); do kubectl get nodes >/dev/null 2>&1 && break; echo \"API noch nicht bereit ($i/36)\"; sleep 5; done",

      "echo '--- Namespace ---'",
      "kubectl get ns immich >/dev/null 2>&1 || kubectl create ns immich",

      "echo '--- Helm (falls fehlt) ---'",
      "command -v helm >/dev/null 2>&1 || (curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash)",

      "echo '--- Base Resources ---'",
      "kubectl apply -f /home/ubuntu/k8s-objects/persistentVolume.yaml",
      "kubectl apply -f /home/ubuntu/k8s-objects/persistentVolumeClaim.yaml -n immich",
      "kubectl apply -f /home/ubuntu/k8s-objects/immich-db-secret.yaml -n immich",

      "echo '--- Redis (NO WAIT) ---'",
      "helm upgrade --install redis oci://registry-1.docker.io/bitnamicharts/redis --namespace immich",

      "echo '--- CloudNativePG Operator (NO WAIT) ---'",
      "helm repo add cnpg https://cloudnative-pg.github.io/charts >/dev/null 2>&1 || true",
      "helm repo update",
      "helm upgrade --install cnpg cnpg/cloudnative-pg --namespace cnpg-system --create-namespace",

      "echo '--- Database ---'",
      "kubectl apply -f /home/ubuntu/k8s-objects/cloudnative-pg.yaml -n immich",

      "echo '--- Immich (NO WAIT) ---'",
      "helm upgrade --install immich oci://ghcr.io/immich-app/immich-charts/immich --namespace immich --create-namespace --values /home/ubuntu/k8s-objects/values.yaml",

      "echo '--- Ingress (Contour) ---'",
      "kubectl apply -f https://projectcontour.io/quickstart/contour.yaml",
      "kubectl apply -f /home/ubuntu/k8s-objects/ingress.yaml",

      "echo '--- Status (non-blocking) ---'",
      "kubectl get nodes || true",
      "kubectl get pods -n immich || true",
      "kubectl get svc -n immich || true",
      "kubectl get svc -n projectcontour || true",

      "LB_IP=$(kubectl get svc envoy -n projectcontour -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)",
      "echo \"Ingress IP: $LB_IP\"",

      "echo '--- Deployment DONE ---'"
    ]
  }

  triggers = {
    objects_hash = sha1(join("", [
      for f in fileset("${path.module}/kubernetes-objects", "**") :
      filesha1("${path.module}/kubernetes-objects/${f}")
    ]))
  }
}
