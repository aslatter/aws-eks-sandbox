
resource "helm_release" "cluster_autoscaler" {
  name      = "cluster-autoscaler"
  namespace = "kube-system"

  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = var.cluster_autoscaler_chart_version

  // TODO - override fullname?
  values = [jsonencode({
    awsRegion : local.aws_region
    autoDiscovery : {
      clusterName : local.cluster_name
    }
    image : {
      tag : var.cluster_autoscaler_image_tag
    }
    rbac : {

      // Configure service account for pod identity
      serviceAccount : {
        name : "cluster-autoscaler"
      }
    }
  })]

  depends_on = [kubectl_manifest.karpenter_node_pool]
}
