resource "null_resource" "deploy_k8s_stack" {
  depends_on = [module.rke2]

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = var.ssh_private_key
    host        = module.rke2.external_ip
  }

  provisioner "remote-exec" {
    inline = ["mkdir -p /home/ubuntu/k8s-objects"]
  }

  provisioner "file" {
    source      = "${path.module}/kubernetes-objects/"
    destination = "/home/ubuntu/k8s-objects/"
  }

  provisioner "remote-exec" {
    inline = [
      "echo '--- Starte Konfiguration ---'",
      "export PATH=$PATH:/var/lib/rancher/rke2/bin",
      "export KUBECONFIG=/etc/rancher/rke2/rke2.yaml",
      "sudo chmod 644 /etc/rancher/rke2/rke2.yaml",

      "kubectl create namespace immich --dry-run=client -o yaml | kubectl apply -f -",

      "if ! command -v helm &> /dev/null; then curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && chmod 700 get_helm.sh && ./get_helm.sh; fi",

      "echo '--- Applying Storage & Secrets into Namespace immich ---'",
      "kubectl apply -f /home/ubuntu/k8s-objects/persistentVolume.yaml",
      "kubectl apply -f /home/ubuntu/k8s-objects/persistentVolumeClaim.yaml -n immich",
      "kubectl apply -f /home/ubuntu/k8s-objects/immich-db-secret.yaml -n immich",

      "echo '--- Installing Redis ---'",
      "helm upgrade --install redis oci://registry-1.docker.io/bitnamicharts/redis --namespace immich --wait",

      "echo '--- Installing CloudNativePG Operator ---'",
      "helm repo add cnpg https://cloudnative-pg.github.io/charts",
      "helm repo update",
      "helm upgrade --install cnpg cnpg/cloudnative-pg --namespace cnpg-system --create-namespace --wait",

      "echo '--- Creating Database Cluster ---'",
      "sleep 15",
      "kubectl apply -f /home/ubuntu/k8s-objects/cloudnative-pg.yaml -n immich",

      "echo '--- Installing Immich ---'",
      "helm upgrade --install immich oci://ghcr.io/immich-app/immich-charts/immich --namespace immich --create-namespace --values /home/ubuntu/k8s-objects/values.yaml",

      "echo '--- Installing Ingress(Controller) ---'",
      "kubectl apply -f https://projectcontour.io/quickstart/contour.yaml",
      "kubectl apply -f /home/ubuntu/k8s-objects/ingress.yaml",

      "echo '--- Warte auf Zuweisung der Floating IP für Envoy... ---'",
      "for i in $(seq 1 30); do LB_IP=$(kubectl get svc envoy -n projectcontour -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null); if [ -n \"$LB_IP\" ]; then echo \"SUCCESS: Ingress IP ist: $LB_IP\"; break; fi; echo \"Warte auf IP... ($i/30)\"; sleep 10; done",
      "kubectl get svc envoy -n projectcontour",

      "echo ''",
      "echo '################################################################'",
      "echo '#  DEPLOYMENT ERFOLGREICH                                      #'",
      "echo '#--------------------------------------------------------------#'",
      "echo \"#  IMMICH URL: http://$LB_IP                                   #\"",
      "echo '################################################################'",
      "echo '--- Deployment abgeschlossen! ---'"
    ]
  }

  triggers = {
    dir_sha1 = sha1(join("", [
      for f in fileset("${path.module}/kubernetes-objects", "*") :
      filesha1("${path.module}/kubernetes-objects/${f}")
    ]))
  }
}
