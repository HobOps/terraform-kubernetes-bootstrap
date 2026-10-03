locals {
  kube_context = "example-c1"
  project_id   = "my-gcp-project"

  # The API VIP is not managed here: kube-vip is deployed with the cluster
  # (k3s manifest), see the module README.
  cilium_values = {
    devices               = ["eth0"]
    routingMode           = "native"
    autoDirectNodeRoutes  = true
    ipv4NativeRoutingCIDR = "10.42.0.0/16"
  }
  cilium_bgp = {
    local_asn = 64620
    peers = [
      { name = "router-v4", address = "10.0.0.1", asn = 65101, families = ["ipv4"] },
    ]
  }
  cilium_lb_ip_pools = {
    gateway = {
      blocks           = ["10.0.0.29/32"]
      service_selector = { matchLabels = { "lb-pool" = "gateway" } }
    }
  }
  cilium_bgp_advertisements = {
    gateway = [{
      advertisementType = "Service"
      service           = { addresses = ["LoadBalancerIP"] }
      selector          = { matchLabels = { "lb-pool" = "gateway" } }
    }]
  }

  argocd_hostname = "argocd.c1.example.com"
  gitops_repo_url = "git@github.com:org/infra.git"
  gitops_path     = "gitops/example-c1"

  gateway_tls_dns_names = [
    "*.c1.example.com",
  ]

  # Path to a SOPS-encrypted secrets file (create outside this example, or adjust).
  secrets_file = "secrets.enc.yaml"

  acme_email = "ops@example.com"
  letsencrypt_dns_zones = [
    "example.com",
    "*.example.com",
  ]
  external_dns_domain_filters = [
    "example.com",
  ]

  argocd_admin_password_mtime = "2026-01-01T00:00:00Z"
  argocd_admin_accounts       = "apiKey, login"

  # Feature flags (module defaults are false; enable what this cluster needs).
  enable_gateway       = true
  enable_cert_manager  = true
  enable_argocd        = true
  enable_external_dns  = true
  enable_reloader      = true
  enable_gitea_actions = false
  gitea_root_url       = null

  chart_versions = {
    cilium        = "1.20.2"
    cert_manager  = "v1.20.3"
    argocd        = "10.1.2"
    external_dns  = "1.21.1"
    reloader      = "2.2.14"
    gitea_actions = "0.1.1"
  }
}
