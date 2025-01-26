

// install the AWS load-balancer ingress-controller
// we won't actually use it as an ingress, but we will
// use its CRDs to link services to existing NLBs.
resource "helm_release" "lb_controller" {
  name      = "aws-load-balancer-controller"
  namespace = "kube-system"

  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.lb_controller_chart_version

  values = [jsonencode({
    clusterName : local.cluster_name
    vpcId : data.terraform_remote_state.eks.outputs.vpc.vpc_id

    enableEndpointSlices : true

    // recommended for use with AWS CNI
    defaultTargetType : "ip"

    // we don't plan on having the controller actually provision
    // AWS resources, but just in case we should tag them.
    defaultTags : local.default_tags

    // configure SA for pod identity
    serviceAccount : {
      name : "aws-lb-controller"
    }
  })]

  depends_on = [kubectl_manifest.karpenter_node_pool]
}
