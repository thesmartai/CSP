resource "null_resource" "deploy_k8s_stack" {
  depends_on = [module.rke2]
  #####
  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(local.ssh_private_key)
    host        = module.rke2.external_ip
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p /home/ubuntu/manifests",
      "mkdir -p /home/ubuntu/argo-apps"
    ]
  }

  provisioner "file" {
    source      = "${path.module}/manifests/"
    destination = "/home/ubuntu/manifests/"
  }

  provisioner "file" {
    source      = "${path.module}/argo_cd/applications/"
    destination = "/home/ubuntu/argo-apps/"
  }

  provisioner "remote-exec" {
    inline = [
      "echo '--- Starte Konfiguration ---'",
      "export PATH=$PATH:/var/lib/rancher/rke2/bin",
      "export KUBECONFIG=/etc/rancher/rke2/rke2.yaml",
      "sudo chmod 644 /etc/rancher/rke2/rke2.yaml",

      # Helm installieren
      "if ! command -v helm &> /dev/null; then curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && chmod 700 get_helm.sh && ./get_helm.sh; fi",

      # installation argo cd
      "echo '--- Installing ArgoCD ---'",
      "helm repo add argo https://argoproj.github.io/argo-helm",
      "helm repo update",
      #idempotent
      "kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -",
      #idempotent
      "helm upgrade --install argocd argo/argo-cd --namespace argocd --set server.service.type=LoadBalancer --wait",
      "kubectl get svc argocd-server -n argocd",

      # Password ausgeben
      "echo '--- ArgoCD Password ---'",
      "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d && echo ''",

      "echo '--- Applying ArgoCD Applications ---'",
      "kubectl apply -f /home/ubuntu/argo-apps/infrastructure.yaml",
      "kubectl apply -f /home/ubuntu/argo-apps/applications.yaml",

      "echo '--------------------------------'",
      "echo 'ArgoCD Deployment abgeschlossen!'",
      "echo '--------------------------------'"
    ]
  }

  #

  triggers = {
    # Führe Deployment nur aus, wenn sich die ArgoCD Application-Definitionen ändern (Bootstrap).
    # Änderungen an normalen Manifesten (manifests/*) werden von ArgoCD via Git erkannt,
    # daher müssen wir hier Terraform nicht neu triggern.
    argo_applications = sha1(join("", [for f in fileset("${path.module}/argo_cd/applications", "*") : filesha1("${path.module}/argo_cd/applications/${f}")]))

    # Auch neu ausführen, wenn wir einen neuen Server haben (IP ändert sich)
    server_ip = module.rke2.external_ip
  }
}



# trigger cd pipeline
