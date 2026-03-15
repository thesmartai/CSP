###########################################################
# Terraform-Konfiguration für einen RKE2-Cluster
# auf der OpenStack-Umgebung der HS Fulda (Private Cloud).
###########################################################

variable "os_project" {
  type = string
}

variable "os_username" {
  type = string
}

variable "os_password" {
  type      = string
  sensitive = true # Verhindert, dass das Passwort in Terraform-Outputs oder Logs erscheint.
}

locals {
  # ACHTUNG: insecure = true deaktiviert die TLS-Zertifikatsprüfung gegenüber der OpenStack API.
  insecure         = true
  auth_url         = "https://private-cloud.informatik.hs-fulda.de:5000"
  object_store_url = "https://10.32.4.32:443"
  region           = "RegionOne"
  # Eigenes CA-Zertifikat für die interne PKI, wird vom OpenStack-Provider genutzt,
  # sofern insecure = false gesetzt wird.
  cacert_file      = "./os-trusted-cas"

  # Cluster-Name wird aus dem Projekt-Namen abgeleitet und klein geschrieben
  cluster_name     = lower("${var.os_project}-k8s")
  image_name       = "ubuntu-22.04-jammy-server-cloud-image-amd64"
  flavor_name      = "m1.medium"
  system_user      = "ubuntu"
  floating_ip_pool = "ext_net"

  # SSH-Keys werden aus dem lokalen Dateisystem des ausführenden Nutzers gelesen.
  # Setzt voraus, dass ~/.ssh/id_rsa(.pub) auf dem CI/CD-Runner oder lokalen Rechner vorhanden ist.
  ssh_pubkey_file = "~/.ssh/id_rsa.pub"
  ssh_private_key = "~/.ssh/id_rsa"

  dns_server   = "10.33.16.100"
  rke2_version = "v1.30.3+rke2r1"

  # Die kubeconfig wird lokal gespeichert, um kubectl-Zugriff nach dem Deployment zu ermöglichen.
  kubeconfig_path = "${path.module}/${lower(var.os_project)}-k8s.rke2.yaml"
}

module "rke2" {
  source = "git::https://github.com/srieger1/terraform-openstack-rke2.git?ref=hsfulda-example"

  insecure            = local.insecure
  bootstrap           = true
  name                = local.cluster_name
  ssh_authorized_keys = [file(local.ssh_pubkey_file)]
  floating_pool       = local.floating_ip_pool

  # ACHTUNG: SSH- und K8s-API-Zugriff sind für alle IP-Adressen geöffnet.
  # Für eine Produktionsumgebung sollten diese auf bekannte IP-Bereiche eingeschränkt werden.
  rules_ssh_cidr = ["0.0.0.0/0"]
  rules_k8s_cidr = ["0.0.0.0/0"]

  servers = [{
    name               = "controller"
    flavor_name        = local.flavor_name
    image_name         = local.image_name
    system_user        = local.system_user
    boot_volume_size   = 6
    rke2_version       = local.rke2_version
    rke2_volume_size   = 10
    rke2_volume_device = "/dev/vdb"
    rke2_config        = <<EOF
write-kubeconfig-mode: "0644"
EOF
  }]

  agents = [
    {
      name               = "worker"
      # Single Worker Node. Ausfall des Workers führt zu Totalausfall der Applikation.
      nodes_count        = 1
      flavor_name        = local.flavor_name
      image_name         = local.image_name
      system_user        = local.system_user
      boot_volume_size   = 10
      rke2_version       = local.rke2_version
      # Großes RKE2-Volume für Container-Images und persistente Daten des Workers.
      rke2_volume_size   = 99
      rke2_volume_device = "/dev/vdb"
    }
  ]

  # Monatliches Backup am 1. jeden Monats um 06:00 Uhr, könnte knapp werden.
  backup_schedule  = "0 6 1 * *"
  backup_retention = 20

  # Ressourcen-Requests für Control-Plane-Komponenten sind niedrig gesetzt
  kube_apiserver_resources = {
    requests = { cpu = "75m", memory = "128M" }
  }
  kube_scheduler_resources = {
    requests = { cpu = "75m", memory = "128M" }
  }
  kube_controller_manager_resources = {
    requests = { cpu = "75m", memory = "128M" }
  }
  etcd_resources = {
    requests = { cpu = "75m", memory = "128M" }
  }

  dns_nameservers4 = [local.dns_server]
  # Agenten, die 30 Sekunden lang nicht erreichbar sind, werden automatisch entfernt.
  ff_autoremove_agent = "30s"
  ff_write_kubeconfig = true
  ff_native_backup    = true
  # Terraform wartet, bis alle Nodes im Ready-Zustand sind, bevor es fortfährt.
  ff_wait_ready       = true

  identity_endpoint     = local.auth_url
  object_store_endpoint = local.object_store_url

  # Alle Container-Images werden über den lokalen Harbor-Registry-Mirror der HS Fulda gezogen.
  registries = {
    mirrors = {
      "*" : { endpoint = ["https://harbor.cs.hs-fulda.de"] }
    }
  }
}

output "floating_ip" {
  value = module.rke2.external_ip
}

provider "openstack" {
  insecure    = local.insecure
  tenant_name = var.os_project
  user_name   = var.os_username
  password    = var.os_password
  auth_url    = local.auth_url
  region      = local.region
  cacert_file = local.cacert_file
}

terraform {
  required_version = ">= 0.14.0"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = ">= 2.0.0"
    }
  }
}
