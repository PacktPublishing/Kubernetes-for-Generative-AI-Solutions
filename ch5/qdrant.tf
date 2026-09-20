resource "helm_release" "qdrant" {
  name       = "qdrant"
  repository = "https://qdrant.github.io/qdrant-helm"
  chart      = "qdrant"
  version    = "1.19.1"
  namespace  = "qdrant"
  create_namespace = true

  # The chart's PVC uses the default StorageClass, so gp3 must exist first.
  # Without this the release is created before addons.tf sets gp3 as default,
  # the PVC stays Pending, and Helm fails with "context deadline exceeded".
  depends_on = [kubernetes_storage_class.default_gp3]
}
