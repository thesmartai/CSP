terraform {
  required_version = ">= 0.14.0"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = ">= 2.0.0"
    }
  }
}

############################
# Variables..
############################

variable "project" {
  type = string
}

variable "username" {
  type      = string
  sensitive = true
}

variable "password" {
  type      = string
  sensitive = true
}

variable "domain_name" {
  type = string
}

# Key kommt aus GitHub Secrets
variable "ssh_public_key" {
  type      = string
  sensitive = true
}

# Schnell vs. gründlich:
# false = schneller kubeconfig, nicht ewig auf "ready" warten
# true  = wartet bis Cluster ready ist (kann lange dauern)
variable "wait_ready" {
  type    = bool
  default = false
}

# Sicherheitsgruppen: nicht hardcoden
variable "rules_ssh_cidr" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "rules_k8s_cidr" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "insecure" {
  type    = bool
  default = true
}

############################
# Locals
############################

locals {
  auth_url         = "https://private-cloud.informatik.hs-fulda.de:5000"
  object_store_url = "https://10.32.4.32:443"
  region           = "RegionOne"
  cacert_file      = "./os-trusted-cas"

  cluster_name     = lower("${var.project}-k8s")
  image_name       = "ubuntu-22.04-jammy-server-cloud-image-amd64"
  flavor_name      = "m1.medium"
  system_user      = "ubuntu"
  floating_ip_pool = "ext_net"

  dns_server   = "10.33.16.100"
  rke2_version = "v1.30.3+rke2r1"

  kubeconfig_path = "${path.module}/${lower(var.project)}-k8s.rke2.yaml"
}

############################
# Provider
############################

provider "openstack" {
  insecure    = var.insecure
  auth_url    = local.auth_url
  region      = local.region
  cacert_file = local.cacert_file

  tenant_name = var.project

  user_name = var.username
  password  = var.password

  user_domain_name    = var.domain_name
  project_domain_name = var.domain_name

  # Wenn du "No suitable endpoint..." bekommst, auf "internal" umstellen.
  endpoint_type = "public"
}

############################
# Module
############################

module "rke2" {
  source = "git::https://github.com/srieger1/terraform-openstack-rke2.git?ref=hsfulda-example"

  insecure            = var.insecure
  bootstrap           = true
  name                = local.cluster_name
  ssh_authorized_keys = [trimspace(var.ssh_public_key)]

  floating_pool  = local.floating_ip_pool
  rules_ssh_cidr = var.rules_ssh_cidr
  rules_k8s_cidr = var.rules_k8s_cidr

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
write-kubeconfig-mode: "0600"
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

  kube_apiserver_resources          = { requests = { cpu = "75m", memory = "128M" } }
  kube_scheduler_resources          = { requests = { cpu = "75m", memory = "128M" } }
  kube_controller_manager_resources = { requests = { cpu = "75m", memory = "128M" } }
  etcd_resources                    = { requests = { cpu = "75m", memory = "128M" } }

  dns_nameservers4 = [local.dns_server]

  # Feature flags
  ff_autoremove_agent = "30s"
  ff_write_kubeconfig = true
  ff_native_backup    = true
  ff_wait_ready       = var.wait_ready

  identity_endpoint     = local.auth_url
  object_store_endpoint = local.object_store_url

  registries = {
    mirrors = {
      "*" = { endpoint = ["https://harbor.cs.hs-fulda.de"] }
    }
  }
}

############################
# Outputs (safe)
############################

output "floating_ip" {
  value = module.rke2.external_ip
}

output "cluster_name" {
  value = local.cluster_name
}

output "kubeconfig_path" {
  value = local.kubeconfig_path
}
