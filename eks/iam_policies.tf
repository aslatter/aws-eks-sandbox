
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
  policy = data.aws_iam_policy_document.cluster_autoscaler.json
}

//
// Permission boundary for roles used in-cluster
//
// A permission-boundary defines the maximum permissions
// a principal may have - it does not actually grant
// any permissions.
//
// We need to keep things fairly general when possible,
// as the JSON policy is limitted to 6,144 characters
// (not including whitespace).
//

data "aws_iam_policy_document" "permission_boundary" {
  statement {
    // example of stuff we want to allow principles running in cluster
    // to generally have access to. These resources don't support coditional
    // access based on resource-tags. We could invent some alternate
    // scoping-mechanism, like name-prefix or similar.
    //
    // because we wouldn't be using off-the-shelf IAM policies for these,
    // I think a strict permission-boundary is less critical.
    effect = "Allow"
    actions = [
      "s3:*",
      "dynamodb:*",
      "sqs:*",
      "events:*"
    ]
    resources = ["*"]
  }
  statement {
    // Where a resource support conditionall-access based on
    // resource tag, we can scope access to this-deployment's
    // resources.
    effect = "Allow"
    actions = [
      "ec2:*",
      "eks-auth:*",
      "elasticloadbalancing:*",
      // not currently used - would be used to add a layer of
      // encryption onto secrets in etcd.
      "kms:*",

      // Not all action matching this filter work with tag-constraints,
      // but the ones we currently use do.
      //
      // Normally I would advocate for keeping permission-boundaries
      // general, but here I'm scoping eks access to read-only out
      // of an abundance of caution.
      "eks:Describe*",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/group"
      values   = ["$${aws:PrincipalTag/group}"]
    }
  }
  statement {
    // some ec2 resources specify use "ec2:ResourceTag" instead
    // of "aws:ResourceTag"
    effect = "Allow"
    actions = [
      "ec2:*",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/group"
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
  statement {
    // the CSI controller doesn't include tags in the 'CreateVolume' call
    // for some reason, so we need to allow all volume-creation and tagging.
    // We still restrict other operations like volume-attach and detach.
    //
    // TODO - There might be some clevel way to prevent changing "protected"
    // tags on volumes from different logical deployments, maybe with an
    // additional Deny policy.
    effect = "Allow"
    actions = [
      "ec2:CreateVolume",
      "ec2:CreateTags"
    ]
    resources = ["arn:${data.aws_partition.current.partition}:ec2:*:*:volume/*"]
  }
  statement {
    // EKS doesn't provide a way to propagate tags into the ASG itself from
    // a managed-node-group, so we can't inject out standard tags. In the actual
    // policies we apply we scope things down.
    effect = "Allow"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "eks_permission_boundary" {
  name   = "cluster_permission_boundary-${local.entropy}"
  policy = data.aws_iam_policy_document.permission_boundary.json
}
