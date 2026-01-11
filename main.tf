###########################################################
# main.tf
###########################################################

terraform {
  required_version = ">= 0.14.0"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = ">= 2.0.0"
    }
  }
}

variable "project" { type = string }
variable "username" { type = string }
variable "password" {
  type      = string
  sensitive = true
}
variable "domain_name" { type = string }

# Optional: skip waiting for full cluster readiness to speed up apply.
variable "wait_ready" {
  type    = bool
  default = false
}

# Keys kommen aus GitHub Secrets
variable "ssh_public_key" {
  type      = string
  sensitive = true
}

variable "ssh_private_key" {
  type      = string
  sensitive = true
}

locals {
  insecure         = true
  auth_url         = "https://private-cloud.informatik.hs-fulda.de:5000"
  object_store_url = "https://10.32.4.32:443"
  region           = "RegionOne"
  cacert_file      = "./os-trusted-cas"

  cluster_name     = lower("${var.project}-k8s")
  image_name       = "ubuntu-22.04-jammy-server-cloud-image-amd64"
  flavor_name      = "m1.large"
  system_user      = "ubuntu"
  floating_ip_pool = "ext_net"

  dns_server   = "10.33.16.100"
  rke2_version = "v1.30.3+rke2r1"

  kubeconfig_path = "${path.module}/${lower(var.project)}-k8s.rke2.yaml"
}

provider "openstack" {
  insecure    = local.insecure
  auth_url    = local.auth_url
  region      = local.region
  cacert_file = local.cacert_file

  # Project (Tenant)
  tenant_name = var.project

  # User auth
  user_name = var.username
  password  = var.password

  # Keystone v3 Domain Fix
  user_domain_name    = var.domain_name
  project_domain_name = var.domain_name

  # Service Catalog Fix (wenn dein Cloud-Catalog "public" endpoints hat)
  # Wenn du weiterhin "No suitable endpoint..." bekommst, probier "internal".
  endpoint_type = "public"
}

module "rke2" {
  source = "git::https://github.com/srieger1/terraform-openstack-rke2.git?ref=hsfulda-example"

  insecure            = local.insecure
  bootstrap           = true
  name                = local.cluster_name
  ssh_authorized_keys = [trimspace(var.ssh_public_key)]
  floating_pool       = local.floating_ip_pool
  rules_ssh_cidr      = ["0.0.0.0/0"]
  rules_k8s_cidr      = ["0.0.0.0/0"]

  servers = [{
    name               = "controller"
    flavor_name        = local.flavor_name
    image_name         = local.image_name
    system_user        = local.system_user
    boot_volume_size   = 20
    rke2_version       = local.rke2_version
    rke2_volume_size   = 50
    rke2_volume_device = "/dev/vdb"
    rke2_config        = <<EOCONFIG
write-kubeconfig-mode: "0600" # Harden kubeconfig permissions.
EOCONFIG
  }]

  agents = [
    {
      name               = "worker"
      nodes_count        = 1
      flavor_name        = local.flavor_name
      image_name         = local.image_name
      system_user        = local.system_user
      boot_volume_size   = 20
      rke2_version       = local.rke2_version
      rke2_volume_size   = 200
      rke2_volume_device = "/dev/vdb"
    }
  ]

  backup_schedule  = "0 6 1 * *"
  backup_retention = 20

  kube_apiserver_resources          = { requests = { cpu = "75m", memory = "128M" } }
  kube_scheduler_resources          = { requests = { cpu = "75m", memory = "128M" } }
  kube_controller_manager_resources = { requests = { cpu = "75m", memory = "128M" } }
  etcd_resources                    = { requests = { cpu = "75m", memory = "128M" } }

  dns_nameservers4    = [local.dns_server]
  ff_autoremove_agent = "30s"
  ff_write_kubeconfig = false # Wir holen uns das Kubeconfig via Terraform Output
  ff_native_backup    = true
  ff_wait_ready       = var.wait_ready # Avoid long waits unless explicitly enabled.

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

#variable "project" { type = string }
output "project" {
  value = var.project

}
#variable "username" { type = string }
output "username" {
  value = var.username

}
#variable "domain_name" { type = string }
output "domain_name" {
  value = var.domain_name

}
