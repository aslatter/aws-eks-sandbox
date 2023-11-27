
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

# TODO

- there are likely required-tags on nodes, subnets, sgs etc
- IRSA
