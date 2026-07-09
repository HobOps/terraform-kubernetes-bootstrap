# kube-vip in ARP (layer 2) mode: holds the VIP for the control-plane (6443)
# and announces LoadBalancer service IPs. The cloud provider assigns IPs to
# LoadBalancer services from the configured pool (single VIP shared by port).
resource "helm_release" "kube_vip" {
  count = var.enable_kube_vip ? 1 : 0

  name       = "kube-vip"
  repository = "https://kube-vip.github.io/helm-charts"
  chart      = "kube-vip"
  version    = local.chart_versions.kube_vip
  namespace  = "kube-system"

  values = [
    yamlencode({
      config = {
        address = var.vip
      }
      env = {
        vip_interface      = var.vip_interface
        vip_arp            = "true"
        cp_enable          = "true"
        svc_enable         = "true"
        svc_election       = "false"
        vip_leaderelection = "true"
        lb_enable          = "true"
        lb_port            = "6443"
        vip_subnet         = "32"
      }
      nodeSelector = {
        "node-role.kubernetes.io/control-plane" = "true"
      }
    })
  ]
}

resource "helm_release" "kube_vip_cloud_provider" {
  count = var.enable_kube_vip ? 1 : 0

  name       = "kube-vip-cloud-provider"
  repository = "https://kube-vip.github.io/helm-charts"
  chart      = "kube-vip-cloud-provider"
  version    = local.chart_versions.kube_vip_cloud_provider
  namespace  = "kube-system"

  values = [
    yamlencode({
      cm = {
        data = {
          cidr-global = "${var.vip}/32"
        }
      }
    })
  ]

  depends_on = [helm_release.kube_vip]
}
