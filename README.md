
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

# TODO


