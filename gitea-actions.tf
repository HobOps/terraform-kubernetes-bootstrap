resource "kubernetes_namespace" "gitea_actions" {
  count = var.enable_gitea_actions ? 1 : 0

  metadata {
    name = "gitea-actions"
  }
}

resource "kubernetes_secret" "gitea_runner_token" {
  count = var.enable_gitea_actions ? 1 : 0

  metadata {
    name      = "gitea-runner-token"
    namespace = kubernetes_namespace.gitea_actions[0].metadata[0].name
  }
  data = {
    token = var.gitea_runner_registration_token
  }
}

resource "helm_release" "gitea_actions" {
  count = var.enable_gitea_actions ? 1 : 0

  name           = "gitea-actions"
  repository     = "https://dl.gitea.com/charts"
  chart          = "actions"
  version        = local.chart_versions.gitea_actions
  namespace      = kubernetes_namespace.gitea_actions[0].metadata[0].name
  take_ownership = true
  wait           = true
  timeout        = 600

  values = [
    yamlencode({
      enabled           = true
      giteaRootURL      = var.gitea_root_url
      existingSecret    = kubernetes_secret.gitea_runner_token[0].metadata[0].name
      existingSecretKey = "token"
      statefulset = {
        replicas = 1
        persistence = {
          size = "10Gi"
        }
        resources = {
          requests = {
            cpu    = "200m"
            memory = "512Mi"
          }
          limits = {
            memory = "2Gi"
          }
        }
        runner = {
          # insecure: skip TLS verify when Gitea's cert is not trusted in-cluster.
          config = <<-EOT
            log:
              level: info
            cache:
              enabled: false
            runner:
              capacity: 1
              timeout: 3h
              insecure: true
              labels:
                - "ubuntu-latest:docker://docker.gitea.com/runner-images:ubuntu-latest"
                - "ubuntu-24.04:docker://docker.gitea.com/runner-images:ubuntu-24.04"
                - "ubuntu-22.04:docker://docker.gitea.com/runner-images:ubuntu-22.04"
            container:
              require_docker: true
              docker_timeout: 300s
          EOT
        }
        dind = {
          rootless = false
          # Docker >= 29.5.2 fixes CopyToContainer when job images symlink /var/run -> /run
          # (act_runner extracts workflow files to /var/run/act/). See moby/moby#52653.
          tag = "29.5.3-dind"
        }
      }
    })
  ]

  depends_on = [kubernetes_secret.gitea_runner_token]
}
