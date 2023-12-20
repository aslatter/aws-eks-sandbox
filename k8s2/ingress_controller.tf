
resource "kubernetes_namespace" "ingress_controller" {
  metadata {
    name = "ingress-controller"
    labels = {
      // https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.1/deploy/pod_readiness_gate/
      "elbv2.k8s.aws/pod-readiness-gate-inject" : "enabled"
    }
  }
}

resource "helm_release" "ingress_controller" {
  name = "nginx-ingress"

  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = kubernetes_namespace.ingress_controller.metadata[0].name

  values = [jsonencode({
    controller : {
      service : {
        type : "ClusterIP"
        ipFamilyPolicy : "PreferDualStack"
        ipFamilies : null
      }

      admissionWebhooks : {
        // I wouldn't mind having this on, but it was timing
        // out for some reason?
        enabled : false
      }
    }
  })]
}

// ask the aws lb-controller to link the ingress service to
// the back-end of our load-balancer.
resource "kubectl_manifest" "ingress_controller_http_tgb" {
  yaml_body = jsonencode({
    apiVersion : "elbv2.k8s.aws/v1beta1"
    kind : "TargetGroupBinding"
    metadata : {
      name : "ingress-controller-http"
      namespace : kubernetes_namespace.ingress_controller.metadata[0].name
    }
    spec : jsondecode(null_resource.ingress_controller_http_tgb.triggers.spec)
  })

  depends_on = [helm_release.lb_controller]

  lifecycle {
    replace_triggered_by = [null_resource.ingress_controller_http_tgb]
  }
}

locals {
  // we do some tricks to force the TargetGroupBinding to
  // get re-created whenever the spec changes, as the CRD
  // doesn't like updates to various fields.
  http_tgb_spec = {
    serviceRef : {
      name : "nginx-ingress-ingress-nginx-controller"
      port : "http"
    }
    targetGroupARN : local.nlb_target_group_http_arn
    targetType : "ip"
  }
}

resource "null_resource" "ingress_controller_http_tgb" {
  triggers = {
    spec = jsonencode(local.http_tgb_spec)
  }
}

