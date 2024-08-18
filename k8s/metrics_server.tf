

// k8s metrics server
resource "helm_release" "k8s_metrics" {
  name      = "k8s-metrics-server"
  namespace = "kube-system"

  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.k8s_metrics_chart_version

  depends_on = [kubectl_manifest.karpenter_node_pool]
}
