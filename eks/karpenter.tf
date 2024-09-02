
// Karpenter-specific resources

//
// event rules
//

// instance health events. This could give us warning about upcoming
// maintenance events for specific EC2 instances.
resource "aws_cloudwatch_event_rule" "karpenter_instance_health" {
  event_pattern = jsonencode({
    source      = ["aws.health"]
    detail-type = ["AWS Health Event"]
  })
}

resource "aws_cloudwatch_event_target" "karpenter_instance_health" {
  rule = aws_cloudwatch_event_rule.karpenter_instance_health.name
  arn  = aws_sqs_queue.karpenter.arn
}

// subscribe to EC2 instance state-changes (start, stop, etc).
resource "aws_cloudwatch_event_rule" "karpenter_instance_state" {
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
  })
}

resource "aws_cloudwatch_event_target" "karpenter_instance_state" {
  rule = aws_cloudwatch_event_rule.karpenter_instance_state.name
  arn  = aws_sqs_queue.karpenter.arn
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
      values = [
        aws_cloudwatch_event_rule.karpenter_instance_health.arn,
        aws_cloudwatch_event_rule.karpenter_instance_state.arn,
      ]
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
