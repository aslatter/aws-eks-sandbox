
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

//
// Permission boundary for roles used in-cluster
//
// A permission-boundary defines the maximum permissions
// a principal may have - it does not actually grant
// any permissions.
//

data "aws_iam_policy_document" "permission_boundary" {
  statement {
    // allow accessing tagged resources
    effect = "Allow"
    actions = [
      // core infrastructure needed to provision EKS
      "ec2:*",
      "eks-auth:*",
      "elasticloadbalancing:*",
      "kms:*",

      // stuff I probably want to use
      "s3:*",
      "ebs:*",
      "dynamodb:*",
      "sqs:*",
      "events:*"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/group"
      values   = ["$${aws:PrincipalTag/group}"]
    }
  }
  statement {
    // allow read-only actions (many of these cannot be
    // scoped to a resource).
    effect = "Allow"
    actions = [
      "autoscaling:Describe*",
      "ec2:Describe*",
      "ec2:Get*",
      "elasticloadbalancing:Describe*",

      // read-only access to ECR
      // see: AmazonEC2ContainerRegistryReadOnly
      "ecr:Get*",
      "ecr:Describe*",
      "ecr:List*",
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage"
    ]
    resources = ["*"]
  }
  statement {
    // allow working with network-interface :-/
    // we cannot tag these. In the policies
    // themselves we try to scope this down.
    //
    // https://github.com/aws/containers-roadmap/issues/1496
    effect    = "Allow"
    actions   = ["ec2:*"]
    resources = ["arn:${data.aws_partition.current.partition}:ec2:*:*:network-interface/*"]
  }
}

resource "aws_iam_policy" "eks_permission_boundary" {
  name   = "cluster_permission_boundary-${local.entropy}"
  policy = data.aws_iam_policy_document.permission_boundary.json
}
