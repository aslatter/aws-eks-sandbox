//
// SQS queues
//

locals {
  queues = {
    karpenterEvents : {
      name : "karpenter"
      // most old events are useless
      message_retention_seconds : 300
    }
  }
}

resource "aws_sqs_queue" "queue" {
  for_each                  = local.queues
  name_prefix               = "${each.value.name}-"
  message_retention_seconds = lookup(each.value, "message_retention_seconds", null)
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue_policy" "queue" {
  for_each  = local.queues
  queue_url = aws_sqs_queue.queue[each.key].id
  // TODO - allow merging in custom queue-policy for integrations that
  // can't use identity policies.
  policy = data.aws_iam_policy_document.sqs_baseline_policy.json
}

// Baseline resource-policy we attach to every queue.
// Adapted from: https://github.com/aws-samples/data-perimeter-policy-examples/blob/main/resource_based_policies/sqs_queue_policy.json
//
// We could adapt from the example RCPs here: https://github.com/aws-samples/data-perimeter-policy-examples/tree/main/resource_control_policies
data "aws_iam_policy_document" "sqs_baseline_policy" {
  statement {
    sid     = "EnforceIdentityPerimeter"
    effect  = "Deny"
    actions = ["sqs:*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = ["*"]
    condition {
      // never allow from outside account
      // this can be adapted to only allow from org
      test     = "StringNotEqualsIfExists"
      variable = "aws:PrincipalAccount"
      values   = [var.aws_account_id]
    }
    condition {
      // allow from AWS services
      // TODO - add confused-deputy-guard for aws-services?
      test     = "BoolIfExists"
      variable = "aws:PrincipalIsAWSService"
      values   = ["false"]
    }
  }
  statement {
    // this is dangerous, because if applied wrongly we can lock ourselves
    // out of managing the queue.
    sid    = "EnforceNetworkPerimeter"
    effect = "Deny"
    // always allow control-plane access so we don't lock ourselves out.
    actions = [
      "sqs:DeleteMessage",
      "sqs:PurgeQueue",
      "sqs:ReceiveMessage",
      "sqs:SendMessage",
      "sqs:StartMessageMoveTask"
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = ["*"]
    // we can also exempt specific principals by tag from this policy
    // (presumably we could exempt resources by tag as well?).
    // if we were using VPC gateways we could exempt them here as well
    condition {
      test     = "NotIpAddressIfExists"
      variable = "aws:SourceIp"
      values   = concat(var.public_access_cidrs, local.public_ips)
    }
    condition {
      // allow principals to flag themselves as exempt from network
      // restrictions
      //
      // This is only safe if we're using an RCP which prevents folks allowed
      // to tag role-sessions from blowing in this tag.
      //
      // I'm not really sure I like this - maybe the creator of the
      // queue could flag specific principals which are allowed through
      // the network perimeter?
      test     = "StringNotEqualsIfExists"
      variable = "aws:PrincipalTag/dp:exclude:network"
      values   = ["true"]
    }
    condition {
      // allow AWS services
      test     = "BoolIfExists"
      variable = "aws:PrincipalIsAWSService"
      values   = ["false"]
    }
    condition {
      // allow AWS services
      test     = "BoolIfExists"
      variable = "aws:ViaAWSService"
      values   = ["false"]
    }
    condition {
      // allow AWS services
      test     = "ArnNotLikeIfExists"
      variable = "aws:PrincipalArn"
      values   = ["arn:${data.aws_partition.current.partition}:iam::${var.aws_account_id}:role/aws-service-role/*"]
    }
  }
  statement {
    sid       = "RequireTLS"
    effect    = "Deny"
    resources = ["*"]
    actions   = ["sqs:*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}
