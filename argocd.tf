resource "helm_release" "argocd" {
  count = var.enable_argocd ? 1 : 0

  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = local.chart_versions.argocd
  namespace        = "argocd"
  create_namespace = true
  timeout          = 600

  values = [
    yamlencode({
      global = {
        domain = var.argocd_hostname
      }
      configs = {
        cm = {
          admin = {
            enabled = true
          }
          "accounts.admin" = var.argocd_admin_accounts
          timeout = {
            reconciliation = "60s"
          }
        }
        params = {
          "server.insecure" = true
        }
        ssh = {
          create = true
        }
        secret = {
          argocdServerAdminPassword      = var.argocd_admin_password_bcrypt
          argocdServerAdminPasswordMtime = var.argocd_admin_password_mtime
        }
      }
      server = {
        # TLS terminates on the shared Gateway; Argo CD serves plain HTTP behind it.
        ingress = {
          enabled = false
        }
        httproute = {
          enabled = true
          hostnames = [
            var.argocd_hostname,
          ]
          parentRefs = [
            {
              name        = var.gateway_name
              namespace   = var.gateway_namespace
              sectionName = "https"
            },
            {
              name        = var.gateway_name
              namespace   = var.gateway_namespace
              sectionName = "http"
            },
          ]
        }
      }
    })
  ]

  lifecycle {
    precondition {
      condition     = var.enable_gateway && var.enable_cert_manager
      error_message = "enable_argocd requires enable_gateway and enable_cert_manager (HTTPRoute + Gateway TLS)."
    }
  }

  depends_on = [
    helm_release.cilium,
    kubectl_manifest.clusterissuer_letsencrypt,
    kubectl_manifest.clusterissuer_letsencrypt_dns01,
    kubectl_manifest.public_gateway,
  ]
}

# App-of-apps: ArgoCD syncs day-2 / business apps under gitops_path.
# Platform components live in this module (Terraform).
resource "kubectl_manifest" "argocd_bootstrap" {
  count = var.enable_argocd ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "bootstrap"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      destination = {
        namespace = "argocd"
        server    = "https://kubernetes.default.svc"
      }
      source = {
        path           = var.gitops_path
        repoURL        = var.gitops_repo_url
        targetRevision = var.gitops_target_revision
        directory = {
          recurse = true
        }
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  })

  depends_on = [helm_release.argocd]
}

# SSH deploy-key repository secret (argocd_repo_auth = "ssh").
resource "kubernetes_secret" "argocd_repo" {
  count = var.enable_argocd && var.argocd_repo_auth == "ssh" ? 1 : 0

  metadata {
    name      = "argocd-repo"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }
  data = {
    url           = var.gitops_repo_url
    type          = "git"
    name          = "gitops"
    project       = "default"
    enableLfs     = "true"
    insecure      = "false"
    sshPrivateKey = var.argocd_repo_ssh_private_key
  }

  depends_on = [helm_release.argocd]
}

# GitHub App credential template (argocd_repo_auth = "github_app"). A repo-creds
# entry matches every repository whose URL starts with `url`.
resource "kubernetes_secret" "argocd_repo_github_app" {
  count = var.enable_argocd && var.argocd_repo_auth == "github_app" ? 1 : 0

  metadata {
    name      = "argocd-repo-github-app"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "repo-creds"
    }
  }
  data = {
    url                     = coalesce(var.argocd_github_app_url, try(regex("^(.*)/[^/]+/?$", var.gitops_repo_url)[0], var.gitops_repo_url))
    type                    = "git"
    githubAppID             = var.argocd_github_app_id
    githubAppInstallationID = var.argocd_github_app_installation_id
    githubAppPrivateKey     = var.argocd_github_app_private_key
  }

  lifecycle {
    precondition {
      condition = (
        var.argocd_github_app_id != null &&
        var.argocd_github_app_installation_id != null &&
        var.argocd_github_app_private_key != null
      )
      error_message = "argocd_repo_auth = \"github_app\" requires argocd_github_app_id, argocd_github_app_installation_id and argocd_github_app_private_key."
    }
  }

  depends_on = [helm_release.argocd]
}
