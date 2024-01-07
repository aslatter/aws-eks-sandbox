
default: k8s2
clean: clean-init

init:
    terraform -chdir=init init
    terraform -chdir=init apply -var-file=../terraform.tfvars -compact-warnings

eks: init
    terraform -chdir=eks init
    terraform -chdir=eks apply -var-file=../terraform.tfvars -compact-warnings

nodes: init
    terraform -chdir=nodes init
    terraform -chdir=nodes apply -var-file=../terraform.tfvars -compact-warnings

k8s2: nodes
    terraform -chdir=k8s2 init
    terraform -chdir=k8s2 apply -var-file=../terraform.tfvars -compact-warnings

clean-init: clean-eks
    terraform -chdir=init destroy -var-file=../terraform.tfvars -compact-warnings

clean-eks: clean-nodes
    terraform -chdir=eks destroy -var-file=../terraform.tfvars -compact-warnings

clean-nodes: clean-k8s2
    terraform -chdir=nodes destroy -var-file=../terraform.tfvars -compact-warnings

clean-k8s2:
    terraform -chdir=k8s2 destroy -var-file=../terraform.tfvars -compact-warnings

kubeconfig:
    terraform -chdir=eks output -json eks | jq -r .kubeconfig > ~/.kube/config
