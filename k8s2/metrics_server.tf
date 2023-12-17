

// k8s metrics server
resource "helm_release" "k8s_metrics" {
  name = "k8s-metrics-server"

  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.11.0"

  namespace = "kube-system"

}
