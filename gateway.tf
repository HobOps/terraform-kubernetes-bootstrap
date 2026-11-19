# Gateway API for the shared public Gateway, implemented by Cilium (cilium.tf)
# or Traefik (traefik.tf), see gateway_controller. The CRDs come first: Cilium
# only enables its Gateway API controller if they exist when the operator
# starts, so helm_release.cilium (and helm_release.traefik) depend on them.
data "http" "gateway_api_crds" {
  count = var.enable_gateway ? 1 : 0

  url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/${var.gateway_api_version}/${var.gateway_api_channel}-install.yaml"
}

data "kubectl_file_documents" "gateway_api_crds" {
  count = var.enable_gateway ? 1 : 0

  content = data.http.gateway_api_crds[0].response_body
}

resource "kubectl_manifest" "gateway_api_crds" {
  for_each = var.enable_gateway ? data.kubectl_file_documents.gateway_api_crds[0].manifests : {}

  yaml_body         = each.value
  server_side_apply = true
  # Take over CRDs previously owned by another manager (e.g. a Traefik chart).
  force_conflicts = true
}

resource "kubernetes_namespace" "gateway" {
  count = var.enable_gateway && var.create_gateway_namespace ? 1 : 0

  metadata {
    name = var.gateway_namespace
  }
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
    kubernetes_namespace.gateway,
    kubectl_manifest.clusterissuer_letsencrypt_dns01,
  ]
}

# Shared public Gateway (class "cilium" or "traefik", per gateway_controller).
# With Cilium, Cilium creates its LoadBalancer Service and
# gateway_infrastructure labels/annotates it (LB IPAM pool, fixed IP). With
# Traefik, the chart's Service fronts it and listener ports are Traefik's
# entryPoint ports (8000/8443), not the Service ports.
resource "kubectl_manifest" "public_gateway" {
  count = var.enable_gateway ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = var.gateway_name
      namespace = var.gateway_namespace
    }
    spec = merge({
      gatewayClassName = var.gateway_controller
      listeners = concat([
        {
          name     = "http"
          protocol = "HTTP"
          port     = local.gateway_listener_ports.http
          allowedRoutes = {
            namespaces = {
              from = "All"
            }
          }
        },
        ], local.enable_gateway_certificate ? [
        {
          name     = "https"
          protocol = "HTTPS"
          port     = local.gateway_listener_ports.https
          tls = {
            mode = "Terminate"
            certificateRefs = concat([
              {
                kind = "Secret"
                name = var.gateway_tls_secret
              }
            ], [for name in var.gateway_extra_tls_secrets : { kind = "Secret", name = name }])
          }
          allowedRoutes = {
            namespaces = {
              from = "All"
            }
          }
        },
      ] : [])
      }, var.gateway_infrastructure == null ? {} : {
      infrastructure = var.gateway_infrastructure
    })
  })

  lifecycle {
    precondition {
      condition     = var.gateway_controller != "cilium" || var.enable_cilium
      error_message = "gateway_controller = \"cilium\" requires enable_cilium. Without Cilium (e.g. GKE), use gateway_controller = \"traefik\"."
    }
  }

  depends_on = [
    kubernetes_namespace.gateway,
    helm_release.cilium,
    kubectl_manifest.gatewayclass_traefik,
    kubectl_manifest.public_gateway_certificate,
  ]
}
