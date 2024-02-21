
// custom IAM policies

// AWS only has a standard policy for IPv4 CNI. This is the recommendation
// for IPv6.
data "aws_iam_policy_document" "cni_ipv6_policy" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:AssignIpv6Addresses",
      "ec2:DescribeInstances",
      "ec2:DescribeTags",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeInstanceTypes"
    ]
    resources = ["*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["ec2:CreateTags"]
    resources = ["arn:${data.aws_partition.current.partition}:ec2:*:*:network-interface/*"]
  }
}

resource "aws_iam_policy" "cni_ipv6_policy" {
  name   = "cni_ipv6_policy-${local.entropy}"
  path   = "/deployment/"
  policy = data.aws_iam_policy_document.cni_ipv6_policy.json
}

// We attach this policy to both the CNI-controller and the EKS control-plane
// itself. AWS IAM does support conditionally-allowing access to ENIs based
// on resource-tags, but EKS doesn't give us any way to apply such tags, so
// instead we throw in a "deny" policy based on ENI-subnet.
data "aws_iam_policy_document" "restrict_eni_access" {
  // scope ENI actions to the private subnets.
  statement {
    effect    = "Deny"
    actions   = ["*"]
    resources = ["arn:${data.aws_partition.current.partition}:ec2:*:*:network-interface/*"]
    condition {
      test     = "ForAllValues:StringNotEquals"
      variable = "ec2:Subnet"
      values   = aws_subnet.private[*].arn
    }
  }
}

resource "aws_iam_policy" "restrict_eni_access" {
  name   = "restrict_eni_access-${local.entropy}"
  path   = "/deployment/"
  policy = data.aws_iam_policy_document.restrict_eni_access.json
}

// This is the policy we attach to the role used by the AWS
// Load Balancer Controller.
//
// https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.5.4/docs/install/iam_policy.json
//
// This is extremely cut-down from the above policy, as we only
// wish to use the lb-controller to register back-ends with an existing
// NLB (as opposed to completely manage NLBs and ALBs on our behalf).
//
// Evaluating/creating a policy that would allow creating load-balancers
// from a principle running in the cluster seems like it would be hard.
data "aws_iam_policy_document" "lb_controler" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAddresses",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcPeeringConnections",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeInstances",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeTags",
      "ec2:GetCoipPoolUsage",
      "ec2:DescribeCoipPools",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeListenerCertificates",
      "elasticloadbalancing:DescribeSSLPolicies",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:DescribeTags"
    ]
    resources = ["*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "lb_controler" {
  name   = "lb_controler-${local.entropy}"
  path   = "/deployment/"
  policy = data.aws_iam_policy_document.lb_controler.json
}

// Policy we attach to the cluster-autoscaler role. It
// operates on ASGs. We scope access based on EKS-generated
// resource-tags, rather than the tags we use in our permission
// boundary, because EKS doesn't give us any control over
// tagging ASGs.
data "aws_iam_policy_document" "cluster_autoscaler" {
  statement {
    // read-only stuff
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplateVersions",
      "eks:DescribeNodegroup"
    ]
    resources = ["*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "ec2:DescribeImages",
      "ec2:GetInstanceTypesFromInstanceRequirements",
    ]
    resources = ["*"]
    // scope to the tags EKS sets for us for our cluster
    // there doesn't seem to be a way with TF to easily get
    // tags onto the ASGs EKS creates for us.
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/k8s.io/cluster-autoscaler/${local.cluster_name}"
      values   = ["owned"]
    }
  }
}

resource "aws_iam_policy" "cluster_autoscaler" {
  name   = "cluster_autoscaler-${local.entropy}"
  path   = "/deployment/"
  policy = data.aws_iam_policy_document.cluster_autoscaler.json
}
