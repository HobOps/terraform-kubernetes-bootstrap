resource "kubernetes_namespace" "external_dns" {
  count = var.enable_external_dns ? 1 : 0

  metadata {
    name = "external-dns"
  }
}

resource "kubernetes_secret" "external_dns_gcp_credentials" {
  count = var.enable_external_dns ? 1 : 0

  metadata {
    name      = "external-dns-gcp-credentials"
    namespace = kubernetes_namespace.external_dns[0].metadata[0].name
  }
  data = {
    "credentials.json" = var.gcp_dns_credentials_json
  }
}

resource "helm_release" "external_dns" {
  count = var.enable_external_dns ? 1 : 0

  name           = "external-dns"
  repository     = "https://kubernetes-sigs.github.io/external-dns/"
  chart          = "external-dns"
  version        = local.chart_versions.external_dns
  namespace      = kubernetes_namespace.external_dns[0].metadata[0].name
  take_ownership = true
  wait           = true
  timeout        = 300

  values = [
    yamlencode({
      provider = {
        name = "google"
      }
      extraArgs = [
        "--google-project=${var.project_id}",
      ]
      domainFilters = var.external_dns_domain_filters
      txtOwnerId    = var.cluster_name
      # upsert-only: never delete records, avoids fights with terraform/dns
      policy = "upsert-only"
      sources = [
        "service",
        "ingress",
        "gateway-httproute",
      ]
      env = [
        {
          name  = "GOOGLE_APPLICATION_CREDENTIALS"
          value = "/etc/secrets/service-account/credentials.json"
        },
      ]
      extraVolumes = [
        {
          name = "google-service-account"
          secret = {
            secretName = kubernetes_secret.external_dns_gcp_credentials[0].metadata[0].name
          }
        },
      ]
      extraVolumeMounts = [
        {
          name      = "google-service-account"
          mountPath = "/etc/secrets/service-account/"
          readOnly  = true
        },
      ]
    })
  ]

  depends_on = [kubernetes_secret.external_dns_gcp_credentials]
}
