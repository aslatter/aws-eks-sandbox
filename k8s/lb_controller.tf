

// install the AWS load-balancer ingress-controller
// we won't actually use it as an ingress, but we will
// use its CRDs to link services to existing NLBs.
resource "helm_release" "lb_controller" {
  name = "aws-load-balancer-controller"

  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.6.2"

  namespace = "kube-system"

  values = [jsonencode({
    clusterName : local.cluster_name
    vpcId : data.terraform_remote_state.eks.outputs.vpc.vpc_id
    // recommended for use with AWS CNI
    defaultTargetType : "ip"

    // we don't plan on having the controller actually provision
    // AWS resources, but just in case we should tag them.
    defaultTags : {
      group : local.group_name
    }

    // configure SA for IRSA
    serviceAccount : {
      name : "aws-lb-controller"
      annotations : {
        "eks.amazonaws.com/role-arn" : data.terraform_remote_state.eks.outputs.pod_roles.kube-system_aws-lb-controller.arn
      }
    }
  })]
}
