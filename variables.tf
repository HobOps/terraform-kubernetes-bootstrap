variable "cluster_name" {
  description = "Short cluster name (kubectl context, external-dns txtOwnerId, etc.)."
  type        = string
}

variable "project_id" {
  description = "GCP project used by cert-manager DNS-01 and external-dns."
  type        = string
}

# --- Feature flags (all off by default) ---

variable "enable_kube_vip" {
  description = "Install kube-vip and kube-vip-cloud-provider."
  type        = bool
  default     = false
}

variable "enable_traefik_gateway" {
  description = "Install Traefik (official Helm chart) with Gateway API (CRDs, GatewayClass, shared Gateway). Assumes the k3s-embedded Traefik is disabled. HTTPS listener needs enable_cert_manager for the Certificate."
  type        = bool
  default     = false
}

variable "enable_cert_manager" {
  description = "Install cert-manager and ClusterIssuers (HTTP-01 + DNS-01)."
  type        = bool
  default     = false
}

variable "enable_argocd" {
  description = "Install Argo CD, repo secret, and bootstrap Application. Requires enable_traefik_gateway and enable_cert_manager for HTTPRoute TLS."
  type        = bool
  default     = false
}

variable "enable_external_dns" {
  description = "Install external-dns (GCP)."
  type        = bool
  default     = false
}

variable "enable_reloader" {
  description = "Install Stakater Reloader."
  type        = bool
  default     = false
}

variable "enable_gitea_actions" {
  description = "Install Gitea Actions runners."
  type        = bool
  default     = false
}

# --- kube-vip ---

variable "vip" {
  description = "Layer-2 VIP for the Kubernetes API and LoadBalancer services (kube-vip)."
  type        = string
  default     = null
}

variable "vip_interface" {
  description = "Host network interface where kube-vip binds the VIP."
  type        = string
  default     = "eth0"
}

# --- Traefik Gateway ---

variable "traefik_load_balancer_ip" {
  description = "Optional static IP for the Traefik LoadBalancer Service. Leave null to let the cloud assign one."
  type        = string
  default     = null
}

variable "gateway_api_version" {
  description = "Kubernetes Gateway API release (standard channel CRDs). The Traefik chart no longer ships these CRDs."
  type        = string
  default     = "v1.5.1"
}

variable "gateway_name" {
  description = "Name of the shared Gateway resource."
  type        = string
  default     = "public-gateway"
}

variable "gateway_namespace" {
  description = "Namespace for the shared Gateway and its TLS Certificate."
  type        = string
  default     = "infrastructure"
}

variable "gateway_tls_secret" {
  description = "Secret name holding the Gateway TLS certificate."
  type        = string
  default     = "public-gateway-tls"
}

variable "gateway_tls_dns_names" {
  description = "DNS SANs for the shared Gateway certificate (DNS-01). Prefer a single wildcard; Let's Encrypt rejects a FQDN covered by the same wildcard in one CSR."
  type        = list(string)
  default     = []
}

# --- cert-manager ---

variable "acme_email" {
  description = "Email registered with the ACME (Let's Encrypt) account."
  type        = string
  default     = null
}

variable "letsencrypt_dns_zones" {
  description = "DNS zones for the DNS-01 ClusterIssuer selector."
  type        = list(string)
  default     = []
}

variable "gcp_dns_credentials_json" {
  description = "GCP service account JSON with DNS admin (cert-manager DNS-01 + external-dns)."
  type        = string
  default     = null
  sensitive   = true
}

# --- Argo CD ---

variable "argocd_hostname" {
  description = "Public hostname for the Argo CD UI (HTTPRoute)."
  type        = string
  default     = null
}

variable "gitops_repo_url" {
  description = "Git repository URL (SSH) that Argo CD syncs for day-2 apps."
  type        = string
  default     = null
}

variable "gitops_path" {
  description = "Path inside the gitops repo for this cluster (app-of-apps)."
  type        = string
  default     = null
}

variable "gitops_target_revision" {
  description = "Git revision (branch/tag/commit) for the bootstrap Application."
  type        = string
  default     = "main"
}

variable "argocd_repo_ssh_private_key" {
  description = "SSH deploy key for the gitops repository."
  type        = string
  default     = null
  sensitive   = true
}

variable "argocd_admin_password_bcrypt" {
  description = "Bcrypt hash for the Argo CD admin password."
  type        = string
  default     = null
  sensitive   = true
}

variable "argocd_admin_password_mtime" {
  description = "ISO-8601 timestamp; bump when rotating the Argo CD admin password."
  type        = string
  default     = null
}

variable "argocd_admin_accounts" {
  description = "Value for configs.cm accounts.admin (e.g. apiKey, login)."
  type        = string
  default     = "apiKey, login"
}

# --- external-dns ---

variable "external_dns_domain_filters" {
  description = "Domains that external-dns is allowed to manage."
  type        = list(string)
  default     = []
}

# --- Gitea Actions ---

variable "gitea_root_url" {
  description = "Gitea instance URL for runner registration."
  type        = string
  default     = null
}

variable "gitea_runner_registration_token" {
  description = "Instance-level Gitea Actions runner registration token."
  type        = string
  default     = null
  sensitive   = true
}

variable "chart_versions" {
  description = "Helm chart versions for platform components. Omitted keys use module defaults."
  type = object({
    kube_vip                = optional(string)
    kube_vip_cloud_provider = optional(string)
    traefik                 = optional(string)
    cert_manager            = optional(string)
    argocd                  = optional(string)
    external_dns            = optional(string)
    reloader                = optional(string)
    gitea_actions           = optional(string)
  })
  default = {}
}

locals {
  chart_versions = {
    kube_vip                = coalesce(try(var.chart_versions.kube_vip, null), "0.9.9")
    kube_vip_cloud_provider = coalesce(try(var.chart_versions.kube_vip_cloud_provider, null), "0.2.10")
    traefik                 = coalesce(try(var.chart_versions.traefik, null), "41.0.2")
    cert_manager            = coalesce(try(var.chart_versions.cert_manager, null), "v1.20.3")
    argocd                  = coalesce(try(var.chart_versions.argocd, null), "10.1.2")
    external_dns            = coalesce(try(var.chart_versions.external_dns, null), "1.21.1")
    reloader                = coalesce(try(var.chart_versions.reloader, null), "2.2.14")
    gitea_actions           = coalesce(try(var.chart_versions.gitea_actions, null), "0.1.1")
  }

  # Gateway TLS Certificate needs both Traefik Gateway and cert-manager.
  enable_gateway_certificate = var.enable_traefik_gateway && var.enable_cert_manager
}
