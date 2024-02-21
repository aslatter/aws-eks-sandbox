
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
of this repo. By default, none of the provisioed resources
admit traffic from the public internete.

Variables you'll need to modify:
* `assume_role` - ARN of IAM Roles to assume when calling AWS
  APIs (inlcuding the Kubernetes API endpoint).
* `aws_account_id` - the account you wish to create the cluster
  in.
* `public_access_cidrs` - IPv4 addresses to allow access from.
  This applies to both the Kubernetes API endpoint as well as
  the load-balancer in front of the cluster.
* `public_access_cidrs_ipv6` - similar to `public_access_cidrs`
  except for IPv6 addresses (note that the Kubernetes API endpoint
  only accepts IPv4 traffic).

The *justfile* coordinates the deployment steps:

* `just` will build out a new cluster
* `just kubeconfig` will *replace* `~/.kube/config` with
  configuration appropriate for connecting to the new
  cluster.
* `just clean` will tear it down

I haven't put too much though into the structure of the
various terraform outputs, sorry.

This is not a "production ready" EKS deployment, as the "public
access" variables control access to both the front-end load-balancer
and the EKS control-plane. Also I have done very little testing
& tuning - this repo was created as a learning exercise.

# What's missing

* TLS (edge or in-cluster)
* DNS
* Node-local DNS
* Node OS-image updgrading

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

This project deploys a Netwok Load Balancer, and a target-group
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

The following demo app should be publically reachable:

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
