
resource "kubectl_manifest" "karpenter_node_class" {
  count = 0
  yaml_body = jsonencode({
    apiVersion : "karpenter.k8s.aws/v1"
    kind : "EC2NodeClass"
    metadata : {
      name : "custom"
    }
    // https://karpenter.sh/v1.0/concepts/nodeclasses/
    // https://karpenter.sh/v1.0/tasks/managing-amis/
    spec : {
      // lots of good stuff here to customize kubelet params that we're not using
      amiFamily : "AL2023"
      amiSelectorTerms : [
        {
          alias : "al2023@latest"
        }
      ]
      kubelet : {
        maxPods : 98
      }
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
      instanceProfile : data.terraform_remote_state.eks.outputs.instance_profiles.node.name

      tags : {
        group : local.group_name
      }

      metadataOptions : {
        httpTokens : "required"
        httpPutResponseHopLimit : 1
      }
    }
  })
}

resource "kubectl_manifest" "karpenter_node_pool" {
  count = 0
  yaml_body = jsonencode({
    apiVersion : "karpenter.sh/v1"
    kind : "NodePool"
    metadata : {
      name : "default"
    }
    // https://karpenter.sh/v1.0/concepts/nodepools/
    spec : {
      limits : {
        cpu : 24
      }
      disruption : {
        // https://karpenter.sh/v1.0/concepts/disruption/
        consolidationPolicy : "WhenEmptyOrUnderutilized"
        consolidateAfter : "5m"
      }
      template : {
        metadata : {
          // tags and annotations for new nodes in this pool
        }
        spec : {
          nodeClassRef : {
            group : "karpenter.k8s.aws" // what is this?
            kind : "EC2NodeClass"       // what is this?
            name : "default"
          }

          taints : []
          startupTaints : []

          expireAfter : "336h" // 14 days
          terminationGracePeriod : "24h"

          requirements : [
            {
              key : "kubernetes.io/arch"
              operator : "In"
              values : ["amd64"]
            },
            {
              key : "kubernetes.io/os"
              operator : "In"
              values : ["linux"]
            },
            {
              key : "karpenter.sh/capacity-type"
              operator : "In"
              values : ["spot", "on-demand"]
            },
            {
              key : "karpenter.k8s.aws/instance-family"
              operator : "In"
              // https://aws.amazon.com/ec2/instance-types/
              // these instance-types are not appropriate for prod
              values : ["t3a", "t3"]
              // something like this for prod:
              // values : ["m7a", "m7i", "m6a", "m6i", "m5a", "m5", "r7a", "r7i", "r6a", "r6i", "r5a", "r5"]
            },
            {
              key : "karpenter.k8s.aws/instance-size"
              operator : "NotIn"
              values : ["nano", "micro"]
            }
          ]
        }
      }
    }
  })

  depends_on = [
    kubectl_manifest.karpenter_node_pool,
  ]
}
