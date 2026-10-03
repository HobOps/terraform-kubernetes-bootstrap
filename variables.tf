variable "cluster_name" {
  description = "Short cluster name (kubectl context, external-dns txtOwnerId, etc.)."
  type        = string
}

variable "project_id" {
  description = "GCP project used by cert-manager DNS-01 and external-dns."
  type        = string
}

# --- Feature flags (all off by default) ---

variable "enable_cilium" {
  description = "Install Cilium (CNI, kube-proxy replacement, LoadBalancer IPAM + BGP, Gateway API). The cluster must have no CNI and no kube-proxy. Everything that needs pods waits for it, so a fresh cluster bootstraps in one apply."
  type        = bool
  default     = true
}

variable "enable_gateway" {
  description = "Install the Gateway API CRDs, the shared public Gateway (class \"cilium\") and, with enable_cert_manager, its TLS Certificate. Enables Cilium's Gateway API controller."
  type        = bool
  default     = false
}

variable "enable_cert_manager" {
  description = "Install cert-manager and ClusterIssuers (HTTP-01 + DNS-01)."
  type        = bool
  default     = false
}

variable "enable_argocd" {
  description = "Install Argo CD, repo secret, and bootstrap Application. Requires enable_gateway and enable_cert_manager for HTTPRoute TLS."
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

# --- Traefik Gateway ---

# --- Cilium ---

variable "cilium_k8s_service_host" {
  description = "API server address Cilium uses (it replaces kube-proxy, so it cannot use the kubernetes Service). Default: the k3s client-side load balancer present on every node."
  type        = string
  default     = "127.0.0.1"
}

variable "cilium_k8s_service_port" {
  description = "API server port for cilium_k8s_service_host (k3s client-side load balancer: 6444)."
  type        = number
  default     = 6444
}

variable "cilium_values" {
  description = "Extra Helm values for Cilium, merged over the module defaults (kube-proxy replacement, IPAM from the node podCIDRs, 2 operator replicas, BGP and Gateway API toggles). Put cluster-specific settings here: devices, routingMode, native routing CIDRs, ipv6, encryption, hubble."
  type        = any
  default     = {}
}

variable "cilium_bgp" {
  description = "Cilium BGP control plane: one instance on the selected nodes with these peers. Peers take every CiliumBGPAdvertisement carrying advertisement_labels. Editing timers, families or graceful restart resets every node's session at once (do it in a maintenance window). null disables BGP."
  type = object({
    name                 = optional(string, "default")
    local_asn            = number
    node_selector        = optional(map(string), { "kubernetes.io/os" = "linux" })
    advertisement_labels = optional(map(string), { advertise = "bgp" })
    peers = list(object({
      name                     = string
      address                  = string
      asn                      = number
      families                 = optional(list(string), ["ipv4"])
      keepalive_seconds        = optional(number, 3)
      hold_seconds             = optional(number, 9)
      connect_retry_seconds    = optional(number, 5)
      graceful_restart_seconds = optional(number) # null = graceful restart off
    }))
  })
  default = null
}

variable "cilium_lb_ip_pools" {
  description = "Cilium LoadBalancer IPAM pools: name => CIDR blocks and an optional serviceSelector (a Kubernetes label selector)."
  type = map(object({
    blocks           = list(string)
    service_selector = optional(any)
  }))
  default = {}
}

variable "cilium_bgp_advertisements" {
  description = "CiliumBGPAdvertisement objects: name => list of spec.advertisements entries. They get cilium_bgp.advertisement_labels, so the peers pick them up."
  type        = map(list(any))
  default     = {}
}

# --- Gateway ---

variable "gateway_infrastructure" {
  description = "Optional spec.infrastructure of the public Gateway: annotations and labels Cilium copies to the Gateway's LoadBalancer Service (e.g. an LB IPAM pool label and lbipam.cilium.io/ips for a fixed IP)."
  type = object({
    annotations = optional(map(string), {})
    labels      = optional(map(string), {})
  })
  default = null
}

variable "gateway_api_version" {
  description = "Kubernetes Gateway API release (standard channel CRDs). Must be the one the Cilium version supports (Cilium 1.20: v1.6.1)."
  type        = string
  default     = "v1.6.1"
}

variable "create_gateway_namespace" {
  description = "Create gateway_namespace. Set to false if it already exists."
  type        = bool
  default     = true
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
    cilium        = optional(string)
    cert_manager  = optional(string)
    argocd        = optional(string)
    external_dns  = optional(string)
    reloader      = optional(string)
    gitea_actions = optional(string)
  })
  default = {}
}

locals {
  chart_versions = {
    cilium        = coalesce(try(var.chart_versions.cilium, null), "1.20.2")
    cert_manager  = coalesce(try(var.chart_versions.cert_manager, null), "v1.20.3")
    argocd        = coalesce(try(var.chart_versions.argocd, null), "10.1.2")
    external_dns  = coalesce(try(var.chart_versions.external_dns, null), "1.21.1")
    reloader      = coalesce(try(var.chart_versions.reloader, null), "2.2.14")
    gitea_actions = coalesce(try(var.chart_versions.gitea_actions, null), "0.1.1")
  }

  # Gateway TLS Certificate needs both the Gateway and cert-manager.
  enable_gateway_certificate = var.enable_gateway && var.enable_cert_manager
}
