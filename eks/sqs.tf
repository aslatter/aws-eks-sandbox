//
// SQS queues
//

locals {
  queues = {
    karpenterEvents : {
      name : "karpenter"
      // most old events are useless
      message_retention_seconds : 300
      // event bridge uses resource-policies to access SQS, so we need
      // to add this in.
      queue_policy = jsonencode({
        Version : "2012-10-17"
        Statement : [
          {
            # Sid : "AllowEventAccess"
            Effect : "Allow"
            Resource : "*"
            Principal : {
              Service : [
                "events.amazonaws.com"
              ]
            }
            Action : "sqs:SendMessage"
            Condition : {
              ArnEquals : {
                "aws:SourceArn" : [for event_rule in aws_cloudwatch_event_rule.karpenter : event_rule.arn]
              }
            }
          }
        ]
      })
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
  policy    = data.aws_iam_policy_document.queue_policy[each.key].json
}

data "aws_iam_policy_document" "queue_policy" {
  for_each                = local.queues
  source_policy_documents = concat([data.aws_iam_policy_document.sqs_baseline_policy.json], try(each.value, "queue_policy", null) != null ? [each.value.queue_policy] : [])
}

// Baseline resource-policy we attach to every queue.
// Adapted from: https://github.com/aws-samples/data-perimeter-policy-examples/blob/main/resource_based_policies/sqs_queue_policy.json
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
      test     = "BoolIfExists"
      variable = "aws:PrincipalIsAWSService"
      values   = ["false"]
    }
  }
  statement {
    // this is dangerous, because if applied wrongly we can lock ourselves
    // out of managing the queue.
    sid     = "EnforceNetworkPerimeter"
    effect  = "Deny"
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
