###########################################################
# deploy.tf (OPTIMIERT)
###########################################################

variable "deploy_apps" {
  type    = bool
  default = true
}

resource "null_resource" "deploy_k8s_stack" {
  count = var.deploy_apps ? 1 : 0

  depends_on = [module.rke2]

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = var.ssh_private_key
    host        = module.rke2.external_ip
    timeout     = "2m"
  }

  # --- Dateien kopieren (schnell, stabil) ---
  provisioner "file" {
    source      = "${path.module}/kubernetes-objects/"
    destination = "/home/ubuntu/k8s-objects/"
  }

  # --- Deployment ---
  provisioner "remote-exec" {
    inline = [
      "set -e",

      "echo '--- Init ---'",
      "export PATH=$PATH:/var/lib/rancher/rke2/bin",
      "export KUBECONFIG=/etc/rancher/rke2/rke2.yaml",
      "sudo chmod 644 /etc/rancher/rke2/rke2.yaml",

      # Namespace (idempotent)
      "kubectl get ns immich >/dev/null 2>&1 || kubectl create ns immich",

      # Helm nur installieren, wenn nötig
      "command -v helm >/dev/null 2>&1 || (curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash)",

      "echo '--- Base Resources ---'",
      "kubectl apply -f /home/ubuntu/k8s-objects/persistentVolume.yaml",
      "kubectl apply -f /home/ubuntu/k8s-objects/persistentVolumeClaim.yaml -n immich",
      "kubectl apply -f /home/ubuntu/k8s-objects/immich-db-secret.yaml -n immich",

      "echo '--- Redis (NO WAIT) ---'",
      "helm upgrade --install redis oci://registry-1.docker.io/bitnamicharts/redis --namespace immich",

      "echo '--- CloudNativePG Operator (NO WAIT) ---'",
      "helm repo add cnpg https://cloudnative-pg.github.io/charts || true",
      "helm repo update",
      "helm upgrade --install cnpg cnpg/cloudnative-pg --namespace cnpg-system --create-namespace",

      "echo '--- Database ---'",
      "kubectl apply -f /home/ubuntu/k8s-objects/cloudnative-pg.yaml -n immich",

      "echo '--- Immich ---'",
      "helm upgrade --install immich oci://ghcr.io/immich-app/immich-charts/immich --namespace immich --values /home/ubuntu/k8s-objects/values.yaml",

      "echo '--- Ingress ---'",
      "kubectl apply -f https://projectcontour.io/quickstart/contour.yaml",
      "kubectl apply -f /home/ubuntu/k8s-objects/ingress.yaml",

      "echo '--- Status (non-blocking) ---'",
      "kubectl get pods -n immich",
      "kubectl get svc -n projectcontour",

      "echo '--- Deployment DONE ---'"
    ]
  }

  # Re-run nur bei YAML-Änderungen
  triggers = {
    objects_hash = sha1(join("", [
      for f in fileset("${path.module}/kubernetes-objects", "**") :
      filesha1("${path.module}/kubernetes-objects/${f}")
    ]))
  }
}
