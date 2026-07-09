# SOPS-encrypted secrets for this cluster:
# - gcp.dns_credentials_json
# - argocd.repo_ssh_private_key / argocd.admin_password_bcrypt
# - gitea.runner_registration_token (only if enable_gitea_actions)
data "sops_file" "cluster_secrets" {
  source_file = local.secrets_file
  input_type  = "yaml"
}

module "bootstrap" {
  source = "../.."

  cluster_name = local.kube_context
  project_id   = local.project_id

  enable_kube_vip        = local.enable_kube_vip
  enable_traefik_gateway = local.enable_traefik_gateway
  enable_cert_manager    = local.enable_cert_manager
  enable_argocd          = local.enable_argocd
  enable_external_dns    = local.enable_external_dns
  enable_reloader        = local.enable_reloader
  enable_gitea_actions   = local.enable_gitea_actions

  vip           = local.vip
  vip_interface = local.vip_interface

  argocd_hostname = local.argocd_hostname
  gitops_repo_url = local.gitops_repo_url
  gitops_path     = local.gitops_path

  gateway_tls_dns_names       = local.gateway_tls_dns_names
  acme_email                  = local.acme_email
  letsencrypt_dns_zones       = local.letsencrypt_dns_zones
  external_dns_domain_filters = local.external_dns_domain_filters

  gcp_dns_credentials_json     = data.sops_file.cluster_secrets.data["gcp.dns_credentials_json"]
  argocd_repo_ssh_private_key  = data.sops_file.cluster_secrets.data["argocd.repo_ssh_private_key"]
  argocd_admin_password_bcrypt = data.sops_file.cluster_secrets.data["argocd.admin_password_bcrypt"]
  argocd_admin_password_mtime  = local.argocd_admin_password_mtime
  argocd_admin_accounts        = local.argocd_admin_accounts

  gitea_root_url                  = local.gitea_root_url
  gitea_runner_registration_token = try(data.sops_file.cluster_secrets.data["gitea.runner_registration_token"], null)

  chart_versions = local.chart_versions
}
