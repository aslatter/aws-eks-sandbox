
default: nodes
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

nodes: k8s
    terraform -chdir=nodes init
    terraform -chdir=nodes apply -var-file=../terraform.tfvars -compact-warnings

clean-init: clean-eks
    terraform -chdir=init destroy

clean-eks: clean-k8s
    terraform -chdir=k8s destroy

clean-k8s: clean-nodes
    terraform -chdir=k8s destroy

clean-nodes:
    terraform -chdir=nodes destroy
