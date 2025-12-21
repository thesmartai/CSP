###########################################################
# main.tf
###########################################################

terraform {
  required_version = ">= 1.3.0"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = ">= 2.0.0"
    }
  }
}

variable "project"  { type = string }
variable "username" { type = string }
variable "password" { type = string }

# Public Key kommt aus GitHub Secret (nicht aus ~/.ssh)
variable "ssh_public_key" {
  type        = string
  description = "SSH public key content (e.g. starts with 'ssh-ed25519 ...')"
}

locals {
  insecure         = true
  auth_url         = "https://private-cloud.informatik.hs-fulda.de:5000"
  object_store_url = "https://10.32.4.32:443"
  region           = "RegionOne"
  cacert_file      = "./os-trusted-cas" # Datei im Repo (oder weglassen, falls nicht nötig)

  cluster_name     = lower("${var.project}-k8s")
  image_name       = "ubuntu-22.04-jammy-server-cloud-image-amd64"
  flavor_name      = "m1.medium"
  system_user      = "ubuntu"
  floating_ip_pool = "ext_net"

  dns_server   = "10.33.16.100"
  rke2_version = "v1.30.3+rke2r1"

  kubeconfig_path = "${path.module}/${lower(var.project)}-k8s.rke2.yaml"
}

provider "openstack" {
  insecure    = local.insecure
  tenant_name = var.project
  user_name   = var.username
  password    = var.password
  auth_url    = local.auth_url
  region      = local.region

  # Wenn du CA brauchst: Datei muss im Repo liegen (oder dynamisch erzeugen via workflow)
  cacert_file = local.cacert_file
}

module "rke2" {
  source = "git::https://github.com/srieger1/terraform-openstack-rke2.git?ref=hsfulda-example"

  insecure            = local.insecure
  bootstrap           = true
  name                = local.cluster_name
  ssh_authorized_keys = [var.ssh_public_key]

  floating_pool  = local.floating_ip_pool
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

  agents = [{
    name               = "worker"
    nodes_count        = 1
    flavor_name        = local.flavor_name
    image_name         = local.image_name
    system_user        = local.system_user
    boot_volume_size   = 10
    rke2_version       = local.rke2_version
    rke2_volume_size   = 100
    rke2_volume_device = "/dev/vdb"
  }]

  backup_schedule  = "0 6 1 * *"
  backup_retention = 20

  kube_apiserver_resources = { requests = { cpu = "75m", memory = "128M" } }
  kube_scheduler_resources = { requests = { cpu = "75m", memory = "128M" } }
  kube_controller_manager_resources = { requests = { cpu = "75m", memory = "128M" } }
  etcd_resources = { requests = { cpu = "75m", memory = "128M" } }

  dns_nameservers4    = [local.dns_server]
  ff_autoremove_agent = "30s"
  ff_write_kubeconfig = true
  ff_native_backup    = true
  ff_wait_ready       = true

  identity_endpoint     = local.auth_url
  object_store_endpoint = local.object_store_url

  registries = {
    mirrors = {
      "*" = { endpoint = ["https://harbor.cs.hs-fulda.de"] }
    }
  }
}

output "floating_ip" {
  value = module.rke2.external_ip
}
