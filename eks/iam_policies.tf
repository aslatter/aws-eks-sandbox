
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

resource "aws_iam_policy" "allow_eks_auto_mode_tags" {
  name = "allow_eks_auto_mode_tags-${local.entropy}"
  path = "/deployment/"
  policy = jsonencode({
    Version: "2012-10-17",
    Statement: [
       {
            Sid: "Compute",
            Effect: "Allow",
            Action: [
                "ec2:CreateFleet",
                "ec2:RunInstances",
                "ec2:CreateLaunchTemplate"
            ],
            Resource: "*",
            Condition: {
                StringEquals: {
                    "aws:RequestTag/eks:eks-cluster-name": "$${aws:PrincipalTag/eks:eks-cluster-name}"
                },
                StringLike: {
                    "aws:RequestTag/eks:kubernetes-node-class-name": "*",
                    "aws:RequestTag/eks:kubernetes-node-pool-name": "*"
                }
            }
        }
    ]
  })
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
    "AmazonEKSWorkerNodePolicy", // non-auto-mode
    "AmazonEKSWorkerNodeMinimalPolicy", // auto-mode
    "AmazonEC2ContainerRegistryReadOnly",
    "AmazonSSMManagedInstanceCore",
  ])

  policy_arn = "${local.iam_role_policy_prefix}/${each.value}"
  role       = aws_iam_role.node.name
}
