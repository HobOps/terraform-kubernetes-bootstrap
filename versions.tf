terraform {
  required_version = ">= 1.3"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0, < 4"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.30, < 3"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.0, < 4"
    }
  }
}
