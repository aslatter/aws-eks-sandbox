
// custom IAM policies

// We attach this policy to both the CNI-controller and the EKS control-plane
// itself. AWS IAM does support conditionally-allowing access to ENIs based
// on resource-tags, but EKS doesn't give us any way to apply such tags, so
// instead we throw in a "deny" policy based on ENI-subnet.
data "aws_iam_policy_document" "restrict_eni_access" {
  // scope ENI actions to the private subnets.
  statement {
    effect    = "Deny"
    actions   = ["*"]
    resources = ["arn:${data.aws_partition.current.partition}:ec2:*:*:subnet/*"]
    condition {
      test     = "StringNotEquals"
      variable = "ec2:SubnetID"
      values   = aws_subnet.private[*].id
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

// Policy attached to the Karpenter pod-role.
// https://karpenter.sh/docs/getting-started/migrating-from-cas/
// https://karpenter.sh/docs/reference/cloudformation/#karpentercontrollerpolicy
data "aws_iam_policy_document" "karpenter" {
  statement {
    // Karpenter
    effect = "Allow"
    // TODO - can some of these be scoped?
    // i.e. we can probably scope 'run instance' and
    // 'tag instance' to the appropriate subnets.
    actions = [
      "ssm:GetParameter",
      "ec2:DescribeImages",
      "ec2:RunInstances",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeAvailabilityZones",
      "ec2:DeleteLaunchTemplate",
      "ec2:CreateTags",
      "ec2:CreateLaunchTemplate",
      // who deletes these?
      "ec2:CreateFleet",
      "ec2:DescribeSpotPriceHistory",
      "pricing:GetProducts"
    ]
    resources = ["*"]
  }
  statement {
    // ConditionalEC2Termination
    effect    = "Allow"
    actions   = ["ec2:TerminateInstances"]
    resources = ["*"]
    // this condition is not meaningful because karpenter can tag any ec2 instance
    condition {
      test     = "StringLike"
      variable = "ec2:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }
  statement {
    // Interruption queue access
    effect = "Allow"
    actions = [
      "sqs:DeleteMessage",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage"
    ]
    resources = [aws_sqs_queue.queue["karpenterEvents"].arn]
  }
  statement {
    // PassNodeIAMRole (!!)
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.node.arn]
  }
  statement {
    // EKSClusterEndpointLookup
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = [aws_eks_cluster.main.arn]
  }
  statement {
    // AllowScopedInstanceProfileCreationActions
    effect    = "Allow"
    actions   = ["iam:CreateInstanceProfile"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${aws_eks_cluster.main.name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/topology.kubernetes.io/region"
      values   = [var.region]
    }
    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }
  }
  statement {
    // AllowScopedInstanceProfileTagActions
    effect    = "Allow"
    actions   = ["iam:TagInstanceProfile"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${aws_eks_cluster.main.name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/topology.kubernetes.io/region"
      values   = [var.region]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${aws_eks_cluster.main.name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/topology.kubernetes.io/region"
      values   = [var.region]
    }
    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }
  }
  statement {
    // AllowScopedInstanceProfileActions
    effect = "Allow"
    actions = [
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:DeleteInstanceProfile",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${aws_eks_cluster.main.name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/topology.kubernetes.io/region"
      values   = [var.region]
    }
    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }
  }
  statement {
    // AllowInstanceProfileReadActions
    effect    = "Allow"
    actions   = ["iam:GetInstanceProfile"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "karpenter" {
  name   = "karpenter-${local.entropy}"
  path   = "/deployment/"
  policy = data.aws_iam_policy_document.karpenter.json
}

//
// Node Role
//
// This policy is a bit different from the others, as it
// is the role assumed by our underlying VMs. It should
// be kept as small as possible, as any pod using
// host-networking can grab the credentials for this role
// through the VM IMDS endpoint.
//
// We cannot disable the IMDS endpoint as this is how the
// VM itself can do things like pull-images (and the pod-
// identity-agent uses the node-role to get auth-tokens).
//

data "aws_iam_policy_document" "node_assume_role_policy" {
  statement {
    sid     = "EKSNodeAssumeRole"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name_prefix = "eks_node_role-"
  path        = "/deployment/"
  // path
  description = "EKS node role"

  assume_role_policy    = data.aws_iam_policy_document.node_assume_role_policy.json
  permissions_boundary  = var.iam_permission_boundary
  force_detach_policies = true
}

// https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_node_group
resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    // required EKS policies
    "AmazonEKSWorkerNodePolicy",
    "AmazonEC2ContainerRegistryReadOnly",
    "AmazonSSMManagedInstanceCore",
  ])

  policy_arn = "${local.iam_role_policy_prefix}/${each.value}"
  role       = aws_iam_role.node.name
}

resource "aws_iam_instance_profile" "node" {
  name_prefix = "eks_node-"
  path        = "/deployment/"
  role        = aws_iam_role.node.name
}
