###########################################################
# main.tf (OPTIMAL)
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

#######################
# Variables
#######################

variable "project" { type = string }
variable "username" { type = string }
variable "domain_name" { type = string }

variable "password" {
  type      = string
  sensitive = true
}

variable "ssh_public_key" {
  type      = string
  sensitive = true
}

variable "ssh_private_key" {
  type      = string
  sensitive = true
}

# Optional: wait for full cluster readiness (slow). Keep false for speed.
variable "wait_ready" {
  type    = bool
  default = false
}

#######################
# Locals
#######################

locals {
  insecure         = true
  region           = "RegionOne"
  auth_url         = "https://private-cloud.informatik.hs-fulda.de:5000"
  object_store_url = "https://10.32.4.32:443"
  cacert_file      = "./os-trusted-cas"

  cluster_name     = lower("${var.project}-k8s")
  image_name       = "ubuntu-22.04-jammy-server-cloud-image-amd64"
  flavor_name      = "m1.large"
  system_user      = "ubuntu"
  floating_ip_pool = "ext_net"

  dns_server   = "10.33.16.100"
  rke2_version = "v1.30.3+rke2r1"
}

#######################
# Provider
#######################

provider "openstack" {
  insecure      = local.insecure
  auth_url      = local.auth_url
  region        = local.region
  cacert_file   = local.cacert_file
  endpoint_type = "public"

  tenant_name         = var.project
  user_name           = var.username
  password            = var.password
  user_domain_name    = var.domain_name
  project_domain_name = var.domain_name
}

#######################
# RKE2 Cluster
#######################

module "rke2" {
  source = "git::https://github.com/srieger1/terraform-openstack-rke2.git?ref=hsfulda-example"

  insecure            = local.insecure
  bootstrap           = true
  name                = local.cluster_name
  ssh_authorized_keys = [trimspace(var.ssh_public_key)]
  floating_pool       = local.floating_ip_pool

  # Offen für Test
  rules_ssh_cidr = ["0.0.0.0/0"]
  rules_k8s_cidr = ["0.0.0.0/0"]

  servers = [{
    name             = "controller"
    flavor_name      = local.flavor_name
    image_name       = local.image_name
    system_user      = local.system_user
    boot_volume_size = 20
    rke2_version     = local.rke2_version

    rke2_volume_size   = 50
    rke2_volume_device = "/dev/vdb"

    rke2_config = <<EOCONFIG
write-kubeconfig-mode: "0600"
EOCONFIG
  }]

  agents = [{
    name             = "worker"
    nodes_count      = 1
    flavor_name      = local.flavor_name
    image_name       = local.image_name
    system_user      = local.system_user
    boot_volume_size = 22
    rke2_version     = local.rke2_version

    # ✅ Unter dem 100GiB-Limit bleiben
    rke2_volume_size   = 99
    rke2_volume_device = "/dev/vdb"
  }]

  backup_schedule  = "0 6 1 * *"
  backup_retention = 20

  kube_apiserver_resources          = { requests = { cpu = "75m", memory = "128Mi" } }
  kube_scheduler_resources          = { requests = { cpu = "75m", memory = "128Mi" } }
  kube_controller_manager_resources = { requests = { cpu = "75m", memory = "128Mi" } }
  etcd_resources                    = { requests = { cpu = "75m", memory = "128Mi" } }

  dns_nameservers4 = [local.dns_server]

  # ✅ Performance / Stabilität
  ff_autoremove_agent = "30s"
  ff_native_backup    = true
  ff_wait_ready       = var.wait_ready

  # ✅ WICHTIG: verhindert den langsamen rsync-wait-loop im Apply
  ff_write_kubeconfig = false

  identity_endpoint     = local.auth_url
  object_store_endpoint = local.object_store_url

  registries = {
    mirrors = {
      "*" = { endpoint = ["https://harbor.cs.hs-fulda.de"] }
    }
  }
}

#######################
# Outputs
#######################

output "floating_ip" {
  description = "Public Floating IP of the cluster"
  value       = module.rke2.external_ip
}

output "application_url" {
  description = "Base URL (Ingress muss separat gesetzt sein)"
  value       = "http://${module.rke2.external_ip}"
}

output "project" {
  value = var.project
}
