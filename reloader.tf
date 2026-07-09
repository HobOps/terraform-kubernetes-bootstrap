resource "helm_release" "reloader" {
  count = var.enable_reloader ? 1 : 0

  name             = "reloader"
  repository       = "https://stakater.github.io/stakater-charts"
  chart            = "reloader"
  version          = local.chart_versions.reloader
  namespace        = "reloader"
  create_namespace = true
  take_ownership   = true
  wait             = true
  timeout          = 300

  values = [
    yamlencode({
      reloader = {
        isArgoRollouts   = false
        isOpenshift      = false
        ignoreSecrets    = false
        ignoreConfigMaps = false
        reloadOnCreate   = false
        reloadStrategy   = "default"
        serviceMonitor = {
          enabled = false
        }
        podMonitor = {
          enabled = false
        }
      }
    })
  ]
}
