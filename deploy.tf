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
      "set -eu pipefail",
      "mkdir -p /home/ubuntu/k8s-objects"
    ]
  }

  provisioner "file" {
    source      = "${path.module}/kubernetes-objects/"
    destination = "/home/ubuntu/k8s-objects/"
  }

  provisioner "remote-exec" {
    script = "${path.module}/install_immich.sh"
  }

  triggers = {
    objects_hash = sha1(join("", [
      for f in fileset("${path.module}/kubernetes-objects", "**") :
      filesha1("${path.module}/kubernetes-objects/${f}")
    ]))
  }
}
