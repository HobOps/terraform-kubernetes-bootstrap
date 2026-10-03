# Cilium: CNI, kube-proxy replacement, LoadBalancer IPAM + BGP and Gateway API.
# The cluster must be installed without a CNI and without kube-proxy (k3s:
# flannel-backend: none, disable-network-policy, disable-kube-proxy). The
# Kubernetes API VIP is NOT managed here: deploy it with the cluster (e.g.
# kube-vip as a k3s manifest from Ansible), see the README.
#
# Everything that needs pods depends on this release, so a fresh cluster is
# bootstrapped in a single terraform apply: Gateway API CRDs -> Cilium ->
# Cilium objects and the rest of the platform.

locals {
  # Defaults for k3s: every k3s node has a client-side load balancer to the
  # API servers on 127.0.0.1:6444, so Cilium does not depend on any VIP.
  cilium_base_values = {
    k8sServiceHost       = var.cilium_k8s_service_host
    k8sServicePort       = var.cilium_k8s_service_port
    kubeProxyReplacement = true
    ipam                 = { mode = "kubernetes" }
    operator             = { replicas = 2 }
    bgpControlPlane      = { enabled = var.cilium_bgp != null }
    gatewayAPI           = { enabled = var.enable_gateway }
  }

  cilium_peer_configs = var.cilium_bgp == null ? [] : [
    for p in var.cilium_bgp.peers : {
      apiVersion = "cilium.io/v2"
      kind       = "CiliumBGPPeerConfig"
      metadata   = { name = p.name }
      spec = {
        timers = {
          keepAliveTimeSeconds    = p.keepalive_seconds
          holdTimeSeconds         = p.hold_seconds
          connectRetryTimeSeconds = p.connect_retry_seconds
        }
        gracefulRestart = merge(
          { enabled = p.graceful_restart_seconds != null },
          p.graceful_restart_seconds != null ? { restartTimeSeconds = p.graceful_restart_seconds } : {},
        )
        families = [for f in p.families : {
          afi            = f
          safi           = "unicast"
          advertisements = { matchLabels = var.cilium_bgp.advertisement_labels }
        }]
      }
    }
  ]

  cilium_cluster_config = var.cilium_bgp == null ? [] : [{
    apiVersion = "cilium.io/v2"
    kind       = "CiliumBGPClusterConfig"
    metadata   = { name = var.cilium_bgp.name }
    spec = {
      nodeSelector = { matchLabels = var.cilium_bgp.node_selector }
      bgpInstances = [{
        name     = var.cilium_bgp.name
        localASN = var.cilium_bgp.local_asn
        peers = [for p in var.cilium_bgp.peers : {
          name          = p.name
          peerASN       = p.asn
          peerAddress   = p.address
          peerConfigRef = { name = p.name }
        }]
      }]
    }
  }]

  cilium_pools = [
    for name, pool in var.cilium_lb_ip_pools : {
      apiVersion = "cilium.io/v2"
      kind       = "CiliumLoadBalancerIPPool"
      metadata   = { name = name }
      spec = merge(
        { blocks = [for b in pool.blocks : { cidr = b }] },
        pool.service_selector == null ? {} : { serviceSelector = pool.service_selector },
      )
    }
  ]

  cilium_advertisements = [
    for name, ads in var.cilium_bgp_advertisements : {
      apiVersion = "cilium.io/v2"
      kind       = "CiliumBGPAdvertisement"
      metadata   = { name = name, labels = try(var.cilium_bgp.advertisement_labels, { advertise = "bgp" }) }
      spec       = { advertisements = ads }
    }
  ]

  cilium_manifests = {
    for m in concat(local.cilium_cluster_config, local.cilium_peer_configs, local.cilium_pools, local.cilium_advertisements) :
    "${m.kind}/${m.metadata.name}" => m
  }
}

resource "helm_release" "cilium" {
  count = var.enable_cilium ? 1 : 0

  name       = "cilium"
  repository = "https://helm.cilium.io"
  chart      = "cilium"
  version    = local.chart_versions.cilium
  namespace  = "kube-system"
  timeout    = 900

  # Module defaults first, then the caller's values (Helm merges them deeply).
  values = [
    yamlencode(local.cilium_base_values),
    yamlencode(var.cilium_values),
  ]

  depends_on = [kubectl_manifest.gateway_api_crds]
}

# Cilium CRs (BGP peers, LB IPAM pools, advertisements). Their CRDs are
# registered by cilium-operator, which is ready once the release is.
resource "kubectl_manifest" "cilium" {
  # The objects have different shapes, so render them first (map of strings).
  for_each = { for k, m in local.cilium_manifests : k => yamlencode(m) if var.enable_cilium }

  yaml_body  = each.value
  depends_on = [helm_release.cilium]
}
