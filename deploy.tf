# Dieses null_resource hat keinen eigenen Cloud-Zustand, es führt nur Remote-Befehle aus.
# Die gesamte K8s-Einrichtung (Helm, ArgoCD, Manifeste) passiert hier mittels SSH.
resource "null_resource" "deploy_k8s_stack" {
  depends_on = [module.rke2]

  # Verbindung zum Controller-Node über die Floating IP des RKE2-Clusters.
  # Der SSH-Key wird aus dem lokalen Dateisystem gelesen, setzt voraus, dass
  # ~/.ssh/id_rsa auf dem ausführenden Rechner vorhanden ist.
  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(local.ssh_private_key)
    host        = module.rke2.external_ip
  }

  # Zielverzeichnisse auf dem Remote-Host vorbereiten.
  provisioner "remote-exec" {
    inline = [
      "mkdir -p /home/ubuntu/manifests",
      "mkdir -p /home/ubuntu/argo-apps"
    ]
  }

  # Kubernetes-Manifeste (DB, Ingress, PVC, Secret) auf den Server übertragen.
  provisioner "file" {
    source      = "${path.module}/manifests/"
    destination = "/home/ubuntu/manifests/"
  }

  # ArgoCD Application-Definitionen übertragen (werden anschließend per kubectl applied)
  provisioner "file" {
    source      = "${path.module}/argo_cd/applications/"
    destination = "/home/ubuntu/argo-apps/"
  }

  provisioner "remote-exec" {
    inline = [
      "echo '--- Starte Konfiguration ---'",
      "export PATH=$PATH:/var/lib/rancher/rke2/bin",
      "export KUBECONFIG=/etc/rancher/rke2/rke2.yaml",

      # ACHTUNG: chmod 644 macht die kubeconfig für alle lokalen Nutzer lesbar.
      # Für eine Produktionsumgebung sollte der Zugriff auf die eigene Gruppe beschränkt bleiben (640)
      "sudo chmod 644 /etc/rancher/rke2/rke2.yaml",

      # Helm nur installieren, wenn es noch nicht vorhanden ist
      "if ! command -v helm &> /dev/null; then curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && chmod 700 get_helm.sh && ./get_helm.sh; fi",

      "echo '--- Installing ArgoCD ---'",
      "helm repo add argo https://argoproj.github.io/argo-helm",
      "helm repo update",

      # --dry-run=client + kubectl apply: Namespace wird nur angelegt, wenn er noch nicht existiert.
      # Verhindert Fehler bei wiederholtem Ausführen
      "kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -",

      # helm upgrade --install: Installiert ArgoCD oder aktualisiert eine bestehende Installation.
      # --wait blockiert bis alle Pods bereit sind, bevor der nächste Schritt ausgeführt wird.
      "helm upgrade --install argocd argo/argo-cd --namespace argocd --set server.service.type=LoadBalancer --wait",
      "kubectl get svc argocd-server -n argocd",

      # ACHTUNG: Das initiale Admin-Passwort wird im Klartext in die Terraform-Logs geschrieben.
      # In einer Produktionsumgebung sollte es direkt nach dem ersten Login geändert
      # und das Secret argocd-initial-admin-secret danach gelöscht werden.
      "echo '--- ArgoCD Password ---'",
      "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d && echo ''",

      "echo '--- Applying ArgoCD Applications ---'",
      # infrastructure.yaml bootstrappt Cluster-weite Komponenten (Ingress, Monitoring, Datenbank-Operator)
      "kubectl apply -f /home/ubuntu/argo-apps/infrastructure.yaml",
      # applications.yaml deployt die eigentliche Anwendung (Immich).
      "kubectl apply -f /home/ubuntu/argo-apps/applications.yaml",

      "echo '--------------------------------'",
      "echo 'ArgoCD Deployment abgeschlossen!'",
      "echo '--------------------------------'"
    ]
  }

  triggers = {
    # Dieses null_resource wird nur neu ausgeführt, wenn sich die ArgoCD Application-Definitionen
    # (argo_cd/applications/*) ändern, nicht bei Änderungen an normalen Manifesten.
    # Änderungen an Manifesten werden von ArgoCD selbst per GitOps-Sync erkannt und eingespielt.
    argo_applications = sha1(join("", [for f in fileset("${path.module}/argo_cd/applications", "*") : filesha1("${path.module}/argo_cd/applications/${f}")]))

    # Bei einer neuen Server-IP (z.B. nach Destroy + Apply) wird das Deployment erneut ausgeführt.
    server_ip = module.rke2.external_ip
  }
}
