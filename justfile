
default: k8s
clean: clean-init

init:
    terraform -chdir=init init
    terraform -chdir=init apply -var-file=../terraform.tfvars -compact-warnings

eks: init
    terraform -chdir=eks init
    terraform -chdir=eks apply -var-file=../terraform.tfvars -compact-warnings

k8s: eks
    terraform -chdir=k8s init
    terraform -chdir=k8s apply -var-file=../terraform.tfvars -compact-warnings

clean-init: clean-eks
    terraform -chdir=init destroy -var-file=../terraform.tfvars -compact-warnings

clean-eks: clean-k8s
    terraform -chdir=eks state rm aws_resourcegroups_group.group || true
    terraform -chdir=eks destroy -var-file=../terraform.tfvars -compact-warnings

clean-k8s:
    terraform -chdir=k8s destroy -var-file=../terraform.tfvars -compact-warnings

kubeconfig:
    terraform -chdir=eks output -json eks | jq -r .kubeconfig > ~/.kube/config
