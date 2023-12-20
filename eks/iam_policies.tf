
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
  policy = data.aws_iam_policy_document.cni_ipv6_policy.json
}

// This is the policy we attach to the role used by the AWS
// Load Balancer Controller.
//
// https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.5.4/docs/install/iam_policy.json
//
// This is extremely cut-down from the above policy, as we only
// wish to use the lb-controller to register back-ends with an existing
// NLB (as opposed to completely manage NLBs and ALBs on our behalf).
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
    // while we're customizing things, we may as well
    // scope the access to the precise resource we wish
    // to modify.
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/group"
      values   = [local.group_name]
    }
  }
}

resource "aws_iam_policy" "lb_controler" {
  name   = "lb_controler-${local.entropy}"
  policy = data.aws_iam_policy_document.lb_controler.json
}