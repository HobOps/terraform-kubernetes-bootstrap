# Gateway API CRDs. The official Traefik chart stopped shipping them, so they
# must exist before the kubernetesGateway provider starts and before the
# GatewayClass / Gateway below are applied.
data "http" "gateway_api_crds" {
  count = var.enable_traefik_gateway ? 1 : 0

  url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/${var.gateway_api_version}/standard-install.yaml"
}

data "kubectl_file_documents" "gateway_api_crds" {
  count = var.enable_traefik_gateway ? 1 : 0

  content = data.http.gateway_api_crds[0].response_body
}

resource "kubectl_manifest" "gateway_api_crds" {
  for_each = var.enable_traefik_gateway ? data.kubectl_file_documents.gateway_api_crds[0].manifests : {}

  yaml_body         = each.value
  server_side_apply = true
  # Take over CRDs previously owned by another manager (e.g. the k3s
  # traefik-crd Helm release, kept in-cluster via helm.sh/resource-policy).
  force_conflicts = true
}

# Install Traefik from the official Helm chart with the Kubernetes Gateway API
# provider enabled. Assumes the k3s-embedded Traefik is disabled on the cluster
# (--disable=traefik); the chart's own Gateway/GatewayClass are disabled because
# they are managed below.
resource "helm_release" "traefik" {
  count = var.enable_traefik_gateway ? 1 : 0

  name             = "traefik"
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = local.chart_versions.traefik
  namespace        = "traefik"
  create_namespace = true

  values = [
    yamlencode({
      providers = {
        kubernetesGateway = {
          enabled = true
        }
      }
      gateway = {
        enabled = false
      }
      gatewayClass = {
        enabled = false
      }
    })
  ]

  depends_on = [kubectl_manifest.gateway_api_crds]
}

resource "kubectl_manifest" "gatewayclass_traefik" {
  count = var.enable_traefik_gateway ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "GatewayClass"
    metadata = {
      name = "traefik"
    }
    spec = {
      controllerName = "traefik.io/gateway-controller"
    }
  })

  depends_on = [helm_release.traefik]
}

# Shared public Gateway. Listener ports must match Traefik entryPoints (8000/8443),
# not the Service ports (80/443).
resource "kubectl_manifest" "public_gateway" {
  count = var.enable_traefik_gateway ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = var.gateway_name
      namespace = var.gateway_namespace
    }
    spec = {
      gatewayClassName = "traefik"
      listeners = [
        {
          name     = "http"
          protocol = "HTTP"
          port     = 8000
          allowedRoutes = {
            namespaces = {
              from = "All"
            }
          }
        },
        {
          name     = "https"
          protocol = "HTTPS"
          port     = 8443
          tls = {
            mode = "Terminate"
            certificateRefs = [
              {
                kind = "Secret"
                name = var.gateway_tls_secret
              }
            ]
          }
          allowedRoutes = {
            namespaces = {
              from = "All"
            }
          }
        },
      ]
    }
  })

  depends_on = [
    kubectl_manifest.gatewayclass_traefik,
    kubectl_manifest.public_gateway_certificate,
  ]
}

resource "kubectl_manifest" "public_gateway_certificate" {
  count = local.enable_gateway_certificate ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = var.gateway_tls_secret
      namespace = var.gateway_namespace
    }
    spec = {
      secretName = var.gateway_tls_secret
      issuerRef = {
        name = "letsencrypt-dns01"
        kind = "ClusterIssuer"
      }
      dnsNames = var.gateway_tls_dns_names
    }
  })

  depends_on = [
    kubectl_manifest.clusterissuer_letsencrypt_dns01,
  ]
}
