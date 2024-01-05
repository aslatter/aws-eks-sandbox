

//
// the aws cli can just as easily make one of these
//
locals {
  kubeconfig = yamlencode({
    apiVersion : "v1",
    kind : "Config",
    preferences : {},
    current-context : "${var.region}:${aws_eks_cluster.main.name}"
    clusters : [
      {
        name : "${var.region}:${aws_eks_cluster.main.name}"
        cluster : {
          server : aws_eks_cluster.main.endpoint
          certificate-authority-data : aws_eks_cluster.main.certificate_authority[0].data,
        }
      }
    ],
    users : [
      {
        name : "${var.region}:${aws_eks_cluster.main.name}"
        user : {
          exec : {
            apiVersion : "client.authentication.k8s.io/v1beta1",
            // TODO - we can pass roles and profiles here
            command : "aws",
            args : ["--region", var.region, "eks", "get-token", "--cluster-name", aws_eks_cluster.main.name, "--output", "json"]
          }
        }
      }
    ]
    contexts : [
      {
        name : "${var.region}:${aws_eks_cluster.main.name}",
        context : {
          cluster : "${var.region}:${aws_eks_cluster.main.name}"
          user : "${var.region}:${aws_eks_cluster.main.name}"
        }
      }
    ]
  })
}
