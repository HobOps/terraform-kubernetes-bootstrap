# Example: complete platform bootstrap

Thin wrapper around the root module. Cluster-specific values live in
`locals.tf`. Secrets come from a SOPS file pointed to by `local.secrets_file`.

## Prerequisites

- `kubectl` context matching `local.kube_context`
- `sops`, `terraform`, `gcloud`
- `GOOGLE_APPLICATION_CREDENTIALS` pointing to a valid GCP service account key

## Setup

1. Copy `secrets.example.yaml` → `secrets.enc.yaml`, fill values, encrypt with SOPS.
2. Edit `locals.tf`, `backend.tf`, and `.sops.yaml` for your environment.
3. Apply:

```bash
cd examples/complete
make init
terraform apply
```

## Argo CD admin password

```bash
sops -d secrets.enc.yaml | yq '.argocd.admin_password'
```

To rotate: update the SOPS bcrypt hash and bump `argocd_admin_password_mtime`
in `locals.tf`, then `terraform apply`.
