
# Learning how to provision EKS through TF.

All of this is inspired by the community VPC and EKS modules,
except slimmed-down.

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

# Instructions

To spin up:

- Create a file names `terraform.tfvars` in the root of this
  repo, customize as you see fit.
- Run `just`

To clean up:

- Run `just cleanup`

If you make some change which requires re-creating the EKS
control-plane, the apply will fail because the cluster node-
groups still exist.

To delete just the node-groups run `just cleanup-nodes`.

# Structure

This project has been broken-up into four different terraform
sub-projects:

- init: generate random labels and names for things
- eks: provision networking and the EKS control-plane
- k8s: perform and Kubernetes updates required for nodes to work
- nodes: provision EKS node-groups
- k8s2: install "core" k8s components

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
