# External Secrets Operator + Vault AppRole auth + ClusterSecretStores.
# ExternalSecrets in app namespaces reference a ClusterSecretStore by name and
# a Vault key (path within the store's KV v2 mount) to materialize K8s Secrets.

resource "kubernetes_namespace" "external_secrets" {
  count = var.enable_external_secrets ? 1 : 0

  metadata {
    name = "external-secrets"
  }
}

resource "helm_release" "external_secrets" {
  count = var.enable_external_secrets ? 1 : 0

  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = local.chart_versions.external_secrets
  namespace        = kubernetes_namespace.external_secrets[0].metadata[0].name
  create_namespace = false
  take_ownership   = true

  values = [
    yamlencode({
      installCRDs = true
    })
  ]

  depends_on = [helm_release.cilium]
}

# Vault AppRole secret_id. roleId is passed inline on each ClusterSecretStore;
# only the secret_id must live in a Secret that ESO reads.
resource "kubernetes_secret" "external_secrets_vault_approle" {
  count = var.enable_external_secrets ? 1 : 0

  metadata {
    name      = "vault-approle"
    namespace = kubernetes_namespace.external_secrets[0].metadata[0].name
  }

  data = {
    secret-id = var.external_secrets_vault_approle_secret_id
  }

  depends_on = [helm_release.external_secrets]
}

resource "kubectl_manifest" "external_secrets_cluster_secret_store" {
  for_each = var.enable_external_secrets ? var.external_secrets_cluster_secret_stores : {}

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = each.key
    }
    spec = {
      provider = {
        vault = {
          server  = var.external_secrets_vault_server
          path    = each.value.path
          version = "v2"
          auth = {
            appRole = {
              path   = var.external_secrets_vault_approle_auth_path
              roleId = var.external_secrets_vault_approle_role_id
              secretRef = {
                name      = kubernetes_secret.external_secrets_vault_approle[0].metadata[0].name
                namespace = kubernetes_secret.external_secrets_vault_approle[0].metadata[0].namespace
                key       = "secret-id"
              }
            }
          }
        }
      }
    }
  })

  depends_on = [
    helm_release.external_secrets,
    kubernetes_secret.external_secrets_vault_approle,
  ]
}
