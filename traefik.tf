# Enable Traefik's Kubernetes Gateway API provider via k3s HelmChartConfig
# (Traefik Gateway is disabled by default on k3s). Skip this path on clusters
# that manage Traefik differently; GatewayClass / Gateway are still created below.
resource "kubectl_manifest" "traefik_helmchartconfig" {
  count = var.enable_traefik_gateway ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "helm.cattle.io/v1"
    kind       = "HelmChartConfig"
    metadata = {
      name      = "traefik"
      namespace = "kube-system"
    }
    spec = {
      valuesContent = <<-VALUES
        providers:
          kubernetesGateway:
            enabled: true
        gateway:
          enabled: false
        gatewayClass:
          enabled: false
      VALUES
    }
  })
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

  depends_on = [kubectl_manifest.traefik_helmchartconfig]
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
