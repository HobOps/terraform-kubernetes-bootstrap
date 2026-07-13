resource "helm_release" "cert_manager" {
  count = var.enable_cert_manager ? 1 : 0

  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = local.chart_versions.cert_manager
  namespace        = "cert-manager"
  create_namespace = true

  values = [
    yamlencode({
      crds = {
        enabled = true
      }
    })
  ]
}

# Service account key used by the DNS-01 solver (Google Cloud DNS).
resource "kubernetes_secret" "letsencrypt_dns01_credentials" {
  count = var.enable_cert_manager ? 1 : 0
  
  metadata {
    name      = "letsencrypt-dns01-credentials"
    namespace = "cert-manager"
  }
  data = {
    "credentials.json" = var.gcp_dns_credentials_json
  }

  depends_on = [helm_release.cert_manager]
}

# HTTP-01 ClusterIssuer (Traefik Ingress class).
resource "kubectl_manifest" "clusterissuer_letsencrypt" {
  count = var.enable_cert_manager ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt"
    }
    spec = {
      acme = {
        email  = var.acme_email
        server = "https://acme-v02.api.letsencrypt.org/directory"
        privateKeySecretRef = {
          name = "cluster-issuer-key-letsencrypt"
        }
        solvers = [
          {
            http01 = {
              ingress = {
                class = "traefik"
              }
            }
          },
        ]
      }
    }
  })

  depends_on = [helm_release.cert_manager]
}

# DNS-01 ClusterIssuer (Google Cloud DNS).
resource "kubectl_manifest" "clusterissuer_letsencrypt_dns01" {
  count = var.enable_cert_manager ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-dns01"
    }
    spec = {
      acme = {
        email  = var.acme_email
        server = "https://acme-v02.api.letsencrypt.org/directory"
        privateKeySecretRef = {
          name = "letsencrypt-dns01"
        }
        solvers = [
          {
            dns01 = {
              cloudDNS = {
                project = var.project_id
                serviceAccountSecretRef = {
                  key  = "credentials.json"
                  name = kubernetes_secret.letsencrypt_dns01_credentials[0].metadata[0].name
                }
              }
            }
            selector = {
              dnsZones = var.letsencrypt_dns_zones
            }
          },
        ]
      }
    }
  })

  depends_on = [
    helm_release.cert_manager,
    kubernetes_secret.letsencrypt_dns01_credentials,
  ]
}
