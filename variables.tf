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

variable "enable_external_secrets" {
  description = "Install External Secrets Operator, the Vault AppRole auth Secret, and the ClusterSecretStores in external_secrets_cluster_secret_stores."
  type        = bool
  default     = false
}

variable "enable_gitea_actions" {
  description = "Install Gitea Actions runners."
  type        = bool
  default     = false
}

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

variable "gateway_controller" {
  description = "Gateway API controller for the shared Gateway: \"cilium\" (needs enable_cilium) or \"traefik\" (installs Traefik, see traefik.tf; for clusters with their own CNI such as GKE). Also the GatewayClass name."
  type        = string
  default     = "cilium"

  validation {
    condition     = contains(["cilium", "traefik"], var.gateway_controller)
    error_message = "gateway_controller must be \"cilium\" or \"traefik\"."
  }
}

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

variable "gateway_api_channel" {
  description = "Gateway API CRD channel to install: \"standard\" or \"experimental\". Managed clusters (e.g. GKE) may enforce the standard channel via admission policy, which excludes TCPRoute/UDPRoute; with Traefik, expose raw TCP with traefik_tcp_listeners instead."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "experimental"], var.gateway_api_channel)
    error_message = "gateway_api_channel must be \"standard\" or \"experimental\"."
  }
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

variable "gateway_extra_tls_secrets" {
  description = "Extra TLS Secrets (same namespace as the Gateway) attached to the HTTPS listener; the controller picks the certificate by SNI."
  type        = list(string)
  default     = []
}

# --- Traefik (gateway_controller = "traefik") ---

variable "traefik_load_balancer_ip" {
  description = "Optional static IP for the Traefik LoadBalancer Service. Leave null to let the cloud assign one."
  type        = string
  default     = null
}

variable "traefik_forwarded_trusted_ips" {
  description = "CIDRs Traefik trusts in X-Forwarded-* headers on the web and websecure entryPoints (forwardedHeaders.trustedIPs). Set it to the fronting L7 load balancer ranges plus the in-cluster peer range so Traefik keeps the real client IP instead of the upstream proxy IP. Empty keeps the chart default (not trusted)."
  type        = list(string)
  default     = []
}

variable "traefik_tcp_listeners" {
  description = "Extra raw-TCP entryPoints opened on the Traefik LoadBalancer Service (name => { port }), exposed on the shared LB IP. Route to them with a Traefik IngressRouteTCP that references the entryPoint by name. Use this where the Gateway API experimental channel (TCPRoute) is unavailable."
  type = map(object({
    port = number
  }))
  default = {}
}

variable "traefik_values" {
  description = "Extra Traefik chart values, merged deeply over the module's (e.g. additional TCP entryPoints under ports)."
  type        = any
  default     = {}
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

variable "letsencrypt_extra_dns01_solvers" {
  description = "Extra DNS-01 solvers for zones hosted in other GCP projects. Same DNS credentials; the service account needs DNS rights on those zones."
  type = list(object({
    project   = string
    dns_zones = list(string)
  }))
  default = []
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

variable "argocd_repo_auth" {
  description = "How Argo CD authenticates to the gitops repository: \"ssh\" (argocd_repo_ssh_private_key) or \"github_app\" (argocd_github_app_*)."
  type        = string
  default     = "ssh"

  validation {
    condition     = contains(["ssh", "github_app"], var.argocd_repo_auth)
    error_message = "argocd_repo_auth must be \"ssh\" or \"github_app\"."
  }
}

variable "argocd_repo_ssh_private_key" {
  description = "SSH deploy key for the gitops repository (argocd_repo_auth = \"ssh\")."
  type        = string
  default     = null
  sensitive   = true
}

variable "argocd_github_app_id" {
  description = "GitHub App ID for the gitops repository (argocd_repo_auth = \"github_app\")."
  type        = string
  default     = null
}

variable "argocd_github_app_installation_id" {
  description = "GitHub App installation ID on the org/repo (argocd_repo_auth = \"github_app\")."
  type        = string
  default     = null
}

variable "argocd_github_app_private_key" {
  description = "GitHub App private key (PEM) for the gitops repository (argocd_repo_auth = \"github_app\")."
  type        = string
  default     = null
  sensitive   = true
}

variable "argocd_github_app_url" {
  description = "URL prefix the GitHub App credential template (repo-creds) matches. null derives it from gitops_repo_url by dropping the repository segment (e.g. https://github.com/org/repo.git => https://github.com/org)."
  type        = string
  default     = null
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

# --- External Secrets ---

variable "external_secrets_vault_server" {
  description = "Vault server URL (e.g. https://vault.example.com) backing the ClusterSecretStores."
  type        = string
  default     = null
}

variable "external_secrets_vault_approle_role_id" {
  description = "Vault AppRole role_id used by every ClusterSecretStore to authenticate."
  type        = string
  default     = null
  sensitive   = true
}

variable "external_secrets_vault_approle_secret_id" {
  description = "Vault AppRole secret_id. Stored in a Kubernetes Secret and referenced by the ClusterSecretStores."
  type        = string
  default     = null
  sensitive   = true
}

variable "external_secrets_vault_approle_auth_path" {
  description = "Vault AppRole auth mount path."
  type        = string
  default     = "approle"
}

variable "external_secrets_cluster_secret_stores" {
  description = "ClusterSecretStores to create (name => { path }), where path is the Vault KV v2 mount backing that store. All stores share the AppRole credentials above."
  type = map(object({
    path = string
  }))
  default = {}
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
    cilium           = optional(string)
    traefik          = optional(string)
    cert_manager     = optional(string)
    argocd           = optional(string)
    external_dns     = optional(string)
    reloader         = optional(string)
    external_secrets = optional(string)
    gitea_actions    = optional(string)
  })
  default = {}
}

locals {
  chart_versions = {
    cilium           = coalesce(try(var.chart_versions.cilium, null), "1.20.2")
    traefik          = coalesce(try(var.chart_versions.traefik, null), "41.0.2")
    cert_manager     = coalesce(try(var.chart_versions.cert_manager, null), "v1.20.3")
    argocd           = coalesce(try(var.chart_versions.argocd, null), "10.1.2")
    external_dns     = coalesce(try(var.chart_versions.external_dns, null), "1.21.1")
    reloader         = coalesce(try(var.chart_versions.reloader, null), "2.2.14")
    external_secrets = coalesce(try(var.chart_versions.external_secrets, null), "2.8.0")
    gitea_actions    = coalesce(try(var.chart_versions.gitea_actions, null), "0.1.1")
  }

  # Gateway TLS Certificate needs both the Gateway and cert-manager.
  enable_gateway_certificate = var.enable_gateway && var.enable_cert_manager

  # Which controller implements the shared Gateway.
  enable_cilium_gateway = var.enable_gateway && var.gateway_controller == "cilium"
  enable_traefik        = var.enable_gateway && var.gateway_controller == "traefik"

  # Traefik listens on its entryPoint ports behind its Service.
  gateway_listener_ports = var.gateway_controller == "traefik" ? { http = 8000, https = 8443 } : { http = 80, https = 443 }
}
