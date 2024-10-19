
// Karpenter-specific resources

//
// event rules
// https://karpenter.sh/docs/reference/cloudformation/#interruption-handling
//

locals {
  event_rules = {
    "instanceHealth" : {
      // https://docs.aws.amazon.com/health/latest/ug/aws-health-concepts-and-terms.html#aws-health-events
      source      = ["aws.health"]
      detail-type = ["AWS Health Event"]
      target      = aws_sqs_queue.karpenter.arn
    }
    "spotInterruption" : {
      // https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-instance-termination-notices.html#ec2-spot-instance-interruption-warning-event
      source      = ["aws.ec2"]
      detail-type = ["EC2 Spot Instance Interruption Warning"]
      target      = aws_sqs_queue.karpenter.arn
    }
    "spotRebalenceRecomendation" : {
      // https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/rebalance-recommendations.html
      source      = ["aws.ec2"]
      detail-type = ["EC2 Instance Rebalance Recommendation"]
      target      = aws_sqs_queue.karpenter.arn
    }
    "instanceState" : {
      // https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/monitoring-instance-state-changes.html
      source      = ["aws.ec2"]
      detail-type = ["EC2 Instance State-change Notification"]
      target      = aws_sqs_queue.karpenter.arn
    }
  }
}

resource "aws_cloudwatch_event_rule" "karpenter" {
  for_each = local.event_rules
  event_pattern = jsonencode({
    source      = each.value.source
    detail-type = each.value.detail-type
  })
}

resource "aws_cloudwatch_event_target" "karpenter" {
  for_each = local.event_rules
  rule     = aws_cloudwatch_event_rule.karpenter[each.key].name
  arn      = each.value.target
}

//
// queue
//

resource "aws_sqs_queue" "karpenter" {
  name_prefix               = "karpenter-"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue_policy" "queues" {
  queue_url = aws_sqs_queue.karpenter.id
  policy    = data.aws_iam_policy_document.karpenter_queue_policy.json
}

data "aws_iam_policy_document" "karpenter_queue_policy" {
  statement {
    effect    = "Allow"
    resources = [aws_sqs_queue.karpenter.arn]
    principals {
      type = "Service"
      identifiers = [
        "events.amazonaws.com",
        "sqs.amazonaws.com"
      ]
    }
    actions = ["sqs:SendMessage"]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [for event_rule in aws_cloudwatch_event_rule.karpenter : event_rule.arn]
    }
  }
  statement {
    sid       = "RequireTLS"
    effect    = "Deny"
    resources = [aws_sqs_queue.karpenter.arn]
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
