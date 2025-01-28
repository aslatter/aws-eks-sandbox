
resource "kubectl_manifest" "auto_mode_node_class" {
  // by default, auto-mode tries to place nodes into the subnets
  // that we've provisioned the EKS-control-plane NICs onto. This
  // isn't appropriate for our networking setup so we need our own
  // node-class.
  yaml_body = jsonencode({
    apiVersion : "eks.amazonaws.com/v1"
    kind : "NodeClass"
    metadata : {
      name : "general"
    }
    spec : {
      ephemeralStorage : {
        iops : 3000
        size : "80Gi"
        throughput : 125
      }

      networkPolicy : "DefaultAllow"
      networkPolicyEventLogs : "Disabled"
      role : "${trimprefix(local.node_role_path, "/")}${local.node_role_name}"

      // we're already behind a NAT-gateway - we don't need an additional layer
      // of SNAT.
      snatPolicy : "Disabled"

      subnetSelectorTerms : [
        {
          tags : {
            "kubernetes.io/cluster/${local.cluster_name}" : "shared"
          }
        }
      ]
      securityGroupSelectorTerms : [
        {
          tags : {
            "kubernetes.io/cluster/${local.cluster_name}" : "shared"
          }
        }
      ]

      tags : local.default_tags
    }
  })
}

resource "kubectl_manifest" "auto_mode_node_pool" {
  yaml_body = jsonencode({
    apiVersion : "karpenter.sh/v1"
    kind : "NodePool"
    metadata : {
      name : "custom"
    }
    spec : {
      disruption : {
        budgets : [{ nodes : "10%" }]
        consolidateAfter : "30s"
        consolidationPolicy : "WhenEmptyOrUnderutilized"
      }
      template : {
        metadata : {}
        spec : {
          expireAfter : "336h"
          nodeClassRef : {
            group : "eks.amazonaws.com"
            kind : "NodeClass"
            name : "general"
          }
          requirements : [
            {
              key : "karpenter.sh/capacity-type"
              operator : "In"
              values : ["spot", "on-demand"]
            },
            {
              key : "eks.amazonaws.com/instance-category"
              operator : "In",
              values : ["c", "m", "r"]
            },
            {
              key : "eks.amazonaws.com/instance-generation"
              operator : "Gt"
              values : ["4"]
            },
            {
              key : "kubernetes.io/arch"
              operator : "In"
              values : ["amd64"]
            },
            {
              key : "kubernetes.io/os"
              operator : "In"
              values : ["linux"]
            }
          ]
          terminationGracePeriod : "24h0m0s"
        }
      }
      limits : {
        cpu : 8
      }
      weight : 10
    }
  })

  depends_on = [kubectl_manifest.auto_mode_node_class]
}
