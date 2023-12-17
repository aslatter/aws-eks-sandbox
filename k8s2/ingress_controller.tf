
resource "kubernetes_namespace" "ingress_controller" {
  metadata {
    name = "ingress-controller"
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
    spec : {
      serviceRef : {
        name : "nginx-ingress-ingress-nginx-controller"
        port : "http"
      }
      targetGroupARN : local.nlb_target_group_http_arn
      targetType : "ip"
    }
  })

  depends_on = [ helm_release.lb_controller ]
}
