
resource "kubernetes_namespace" "gateway_controller" {
  metadata {
    name = "gateway-controller"
    labels = {
      // https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.1/deploy/pod_readiness_gate/
      "elbv2.k8s.aws/pod-readiness-gate-inject" : "enabled"
    }
  }
}

// ideally we would use the CRDs helm-chart, but that can't
// actually be managed by helm because the tracking k8s secret
// is too big.
//
// I also tried using the k8s-manifest tf resource to load a
// file containing the CRDs, but something was truncating the file.
resource "helm_release" "gateway_controller" {
  name      = "envoy-gateway"
  namespace = kubernetes_namespace.gateway_controller.metadata[0].name

  repository = "oci://docker.io/envoyproxy"
  chart      = "gateway-helm"
  version    = var.envoy_gateway_chart_version

  skip_crds = false

  values = [jsonencode({})]

  depends_on = [
    kubectl_manifest.karpenter_node_pool
  ]
}

resource "kubectl_manifest" "gateway_class" {
  yaml_body = jsonencode({
    apiVersion : "gateway.networking.k8s.io/v1"
    kind : "GatewayClass"
    metadata : {
      name : "eg"
    }
    spec : {
      controllerName : "gateway.envoyproxy.io/gatewayclass-controller"
    }
  })

  depends_on = [helm_release.gateway_controller]
}

resource "kubectl_manifest" "gateway" {
  yaml_body = jsonencode({
    apiVersion : "gateway.networking.k8s.io/v1"
    kind : "Gateway"
    metadata : {
      name : "eg"
    }
    spec : {
      gatewayClassName : "eg"
      infrastructure : {
        parametersRef : {
          group : "gateway.envoyproxy.io"
          kind : "EnvoyProxy"
          name : "eg-proxy-config"
          # namespace: kubernetes_namespace.gateway_controller.metadata[0].name
        }
      }
      listeners : [
        {
          name : "http"
          protocol : "HTTP"
          port : 80
        }
      ]
    }
  })

  depends_on = [
    kubectl_manifest.gateway_class,
    kubectl_manifest.gateway_envoyproxy_config
  ]
}

// We need to configure the gateway-class so that:
// - the service is of type "ClusterIP"
// - the service has a deterministic name
//
// So that we can construct a TGB to link the gateway
// class to our load-balancer.
//
// This is also where we would do things like configure
// more than one replica of the data-plane, for example.
resource "kubectl_manifest" "gateway_envoyproxy_config" {
  yaml_body = jsonencode({
    apiVersion : "gateway.envoyproxy.io/v1alpha1"
    kind : "EnvoyProxy"
    metadata : {
      name : "eg-proxy-config"
      namespace : "default"
    }
    spec : {
      provider : {
        type : "Kubernetes"
        kubernetes : {
          envoyService : {
            type : "ClusterIP"
            name : "eg-proxy"
          }
        }
      }
    }
  })

  depends_on = [helm_release.gateway_controller]
}

// ask the aws lb-controller to link the ingress service to
// the back-end of our load-balancer.
resource "kubectl_manifest" "gateway_controller_http_tgb" {
  yaml_body = jsonencode({
    apiVersion : "elbv2.k8s.aws/v1beta1"
    kind : "TargetGroupBinding"
    metadata : {
      name : "gateway-controller-http"
      namespace : kubernetes_namespace.gateway_controller.metadata[0].name
    }
    spec : jsondecode(null_resource.gateway_controller_http_tgb.triggers.spec)
  })

  depends_on = [kubectl_manifest.gateway]

  lifecycle {
    replace_triggered_by = [null_resource.gateway_controller_http_tgb]
  }
}

locals {
  // we do some tricks to force the TargetGroupBinding to
  // get re-created whenever the spec changes, as the CRD
  // doesn't like updates to various fields.
  http_tgb_spec = {
    serviceRef : {
      name : "eg-proxy"
      port : "http-80"
    }
    targetGroupARN : local.nlb_target_group_http_arn
    targetType : "ip"
  }
}

resource "null_resource" "gateway_controller_http_tgb" {
  triggers = {
    spec = jsonencode(local.http_tgb_spec)
  }
}

