# Traefik as the Gateway API controller (gateway_controller = "traefik").
# For clusters that do not run Cilium as their CNI, e.g. GKE: set
# enable_cilium = false, enable_gateway = true and gateway_controller =
# "traefik". The shared Gateway in gateway.tf then uses class "traefik".
#
# Resource addresses match v0.x (helm_release.traefik,
# kubectl_manifest.gatewayclass_traefik), so callers upgrading from the v0.x
# Traefik line keep their state.

locals {
  traefik_base_values = merge(
    {
      providers = {
        kubernetesGateway = {
          enabled             = true
          experimentalChannel = var.gateway_api_channel == "experimental"
        }
      }
      # The Gateway and GatewayClass are managed by this module.
      gateway = {
        enabled = false
      }
      gatewayClass = {
        enabled = false
      }
    },
    # web/websecure forwardedHeaders and extra raw-TCP entryPoints share the
    # chart's `ports` map, so build it once: a shallow merge here would let one
    # `ports` key overwrite the other. The chart deep-merges it with its
    # default web/websecure ports.
    length(var.traefik_forwarded_trusted_ips) > 0 || length(var.traefik_tcp_listeners) > 0 ? {
      ports = merge(
        # Trust X-Forwarded-* only from these sources (the fronting load
        # balancer and in-cluster peers), so apps see the real client IP.
        length(var.traefik_forwarded_trusted_ips) > 0 ? {
          web = {
            forwardedHeaders = {
              trustedIPs = var.traefik_forwarded_trusted_ips
            }
          }
          websecure = {
            forwardedHeaders = {
              trustedIPs = var.traefik_forwarded_trusted_ips
            }
          }
        } : {},
        {
          for name, listener in var.traefik_tcp_listeners : name => {
            port        = listener.port
            exposedPort = listener.port
            protocol    = "TCP"
            expose = {
              default = true
            }
          }
        },
      )
    } : {},
    var.traefik_load_balancer_ip != null ? {
      service = {
        spec = {
          loadBalancerIP = var.traefik_load_balancer_ip
        }
      }
    } : {},
  )
}

# Official Helm chart with the Kubernetes Gateway API provider. On k3s, disable
# the embedded Traefik first (--disable=traefik).
resource "helm_release" "traefik" {
  count = local.enable_traefik ? 1 : 0

  name             = "traefik"
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = local.chart_versions.traefik
  namespace        = "traefik"
  create_namespace = true

  # Module defaults first, then the caller's values (Helm merges them deeply).
  values = [
    yamlencode(local.traefik_base_values),
    yamlencode(var.traefik_values),
  ]

  depends_on = [kubectl_manifest.gateway_api_crds]
}

resource "kubectl_manifest" "gatewayclass_traefik" {
  count = local.enable_traefik ? 1 : 0

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
