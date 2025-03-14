
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
    }
    "spotInterruption" : {
      // https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-instance-termination-notices.html#ec2-spot-instance-interruption-warning-event
      source      = ["aws.ec2"]
      detail-type = ["EC2 Spot Instance Interruption Warning"]
    }
    "spotRebalenceRecomendation" : {
      // https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/rebalance-recommendations.html
      source      = ["aws.ec2"]
      detail-type = ["EC2 Instance Rebalance Recommendation"]
    }
    "instanceState" : {
      // https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/monitoring-instance-state-changes.html
      source      = ["aws.ec2"]
      detail-type = ["EC2 Instance State-change Notification"]
    }
  }
}

resource "aws_cloudwatch_event_rule" "karpenter" {
  for_each    = local.event_rules
  name_prefix = "${each.key}-"
  event_pattern = jsonencode({
    source      = each.value.source
    detail-type = each.value.detail-type
  })
}

resource "aws_cloudwatch_event_target" "karpenter" {
  for_each = local.event_rules
  rule     = aws_cloudwatch_event_rule.karpenter[each.key].name
  arn      = aws_sqs_queue.queue["karpenterEvents"].arn

  role_arn = aws_iam_role.karpenter_events.arn
}

resource "aws_iam_role" "karpenter_events" {
  name_prefix          = "karpenter-events"
  path                 = "/deployment/"
  permissions_boundary = var.iam_permission_boundary

  assume_role_policy = data.aws_iam_policy_document.karpenter_event_rule_trust_policy.json

  tags = {
    "dp:exclude:network" : "true"
  }
}

resource "aws_iam_role_policy" "karpenter_events" {
  name = "sqs-access"
  role = aws_iam_role.karpenter_events.name

  policy = data.aws_iam_policy_document.karpenter_event_rule_policy.json
}

data "aws_iam_policy_document" "karpenter_event_rule_policy" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.queue["karpenterEvents"].arn]
  }
}

data "aws_iam_policy_document" "karpenter_event_rule_trust_policy" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_account_id]
    }
  }
}
