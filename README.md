
# Learning how to provision EKS through TF.

All of this is inspired by the community VPC and EKS modules. In
particular the VPC design follows the same basic structure as
the community module. The EKS community module is invaluable
for understanding how to work with EKS and Terraform.

Links:
* https://github.com/terraform-aws-modules/terraform-aws-vpc
* https://github.com/terraform-aws-modules/terraform-aws-eks

Other important resources:
* [VPC User Guide](https://docs.aws.amazon.com/vpc/latest/userguide/index.html)
* [EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/index.html)
* [EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/)

Other important reference material:
* [Network Load Balancer User Guide](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/index.html)
* [All AWS IAM Documentation](https://docs.aws.amazon.com/iam/)
* [IAM actions, resources, and condition keys for all services](https://docs.aws.amazon.com/service-authorization/latest/reference/reference_policies_actions-resources-contextkeys.html)

# Using

Create a file `terraform.tfvar` in the root of your checkout
of this repo. By default, none of the provisioned resources
admit traffic from the public internet.

Variables you'll need to modify:

* `region` - AWS region
* `assume_role` - IAM role ARN to assume when calling AWS APIs
* `iam_permission_boundary` - IAM policy ARN to apply to created roles
* `aws_account_id` - AWS account id to apply changes to
* `public_access_cidrs` - list of IPv4 CIDRs to allow access to various resources

The Terraform provider authenticates against AWS APIs using the
current AWS-config-profile (and then assumes the role above).

The *justfile* coordinates the deployment steps:

* `just` will build out a new cluster
* `just kubeconfig` will *replace* `~/.kube/config` with
  configuration appropriate for connecting to the new
  cluster.
* `just clean` will tear it down

I haven't put too much though into the structure of the
various terraform outputs, sorry.

This repo is constructed as a learning exercise and to learn how
to provision things on AWS and is not intended to be "production
ready".

Noted deficiencies:

* I don't really install workloads into the cluster when I test
  upgrades
* The ingress-controller does not update CRDs
* There's no CSI controller installed
* The same IP-allwo-list is applied to both the front-end
  load-balancer as the k8s API server and other resources
* No in-cluster TLS
* No workload observability

# Structure

This project has been broken-up into multiple terraform
sub-projects:

- init: generate random labels and names for things
- eks: provision networking, the EKS control-plane, and managed node-group
- k8s: install "core" k8s components

# Details

We provision three types of sub-nets:

- public
- private
- intra

The public subnet has an egress route to an internet gateway, and
is intended to hold things like EKS load-balancers.

The private subnet has an egress route to a NAT gateway, and is
intended to hold the EKS worker-nodes.

The "intra" subnet has no route to the public internet, and is
intended to hold the ENIs for EKS control-plane access.

The variable "cluster_az_count" determines how many AZs we will
provision "intra" subnets into, and must be at least two.

The variable "node_az_count" determines how many AZs we will
provision public/private subnet-pairs into.

We will provision one NAT gateway per private subnet.

# Ingress

This project deploys a Network Load Balancer, and a target-group
which port-80 on this load-balancer is redirected to. The ARN for
this target-group is an output of the 'eks' project.

We then install nginx-ingress into the cluster, and tell the AWS
Load Balancer Controller to use the nginx-controller as the back-end
for the load-balancer on port 80.

To test out the connection:

```
curl "$(terraform -chdir=eks output -json vpc | jq -r .nlb_dns_name)"
```

This should return 404, as there aren't any ingress-objects installed
in the cluster.

I haven't given much thought to how dual-AZ load-balancing should
work in EKS, so that part of this setup may need tweaks.

I also have put no thought into the health-check timings of the NLB,
nor have I configured the pod-readiness gate to make what I'm doing
safe.

The following demo app should be publicly reachable:

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-node
  labels:
    app: hello-node
spec:
  replicas: 3
  selector:
    matchLabels:
      app: hello-node
  template:
    metadata:
      labels:
        app: hello-node
    spec:
      containers:
      - name: hello-node
        image: registry.k8s.io/e2e-test-images/agnhost:2.39
        ports:
          - name: http
            containerPort: 8080
        command: ["/agnhost", "netexec", "--http-port=8080"]
---
apiVersion: v1
kind: Service
metadata:
  name: hello-node
  labels:
    app: hello-node
spec:
  selector:
    app: hello-node
  ports:
    - protocol: TCP
      port: 80
      targetPort: http
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hello-node
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /testpath
        pathType: Prefix
        backend:
          service:
            name: hello-node
            port:
              name: http
```

# Upgrade Checklist

We have a number of versioned components to track:

+ Kubernetes

  Visit: https://docs.aws.amazon.com/eks/latest/userguide/platform-versions.html

+ Kubernetes Metrics Helm Chart

  Visit: https://github.com/kubernetes-sigs/metrics-server/releases

+ AWS Load Balancer Controller Helm Chart

  + Chart: https://artifacthub.io/packages/helm/aws/aws-load-balancer-controller
  + Chart: https://github.com/aws/eks-charts/blob/master/stable/aws-load-balancer-controller/Chart.yaml
  + Documentation: https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html
  + Controller: https://github.com/kubernetes-sigs/aws-load-balancer-controller

  Review release-notes in case CDRs need to be updated (upgrading the helm chart
  will not upgrade CRDs).

+ NGINX Ingress Controller Helm Chart

  Check releases here: https://github.com/kubernetes/ingress-nginx

+ Karpenter Helm Chart

  + Visit: https://github.com/aws/karpenter-provider-aws/tree/main/charts
  + Releases scope to v1+: https://github.com/aws/karpenter-provider-aws/releases?q=v1.&expanded=true

  Review release-notes for CRD updates
