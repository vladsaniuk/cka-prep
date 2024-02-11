# CKA prep      
To get up and running you need to have your SSH public key available at ~/.ssh/id_rsa.pub      
You need to supply your IP, when running terraform, i.e. terraform plan -var 'my_ip=192.158.1.38/32'      
Scripts to bootstrap control plane and nodes are idempotent - they will not break anything, if run again.   
You can also provide nodes_count var to manage nodes count, default is 2, so you'll have 1 control plane and 2 nodes.     

## Cluster with Nginx Ingress Controller       
Spin-up cluster:
```
cd cluster-bootstrap
terraform init -var 'my_ip=185.189.245.112/32' -var 'nodes_count=1' -upgrade
terraform plan -var 'my_ip=185.189.245.112/32' -var 'nodes_count=1' -out=plan.tfplan
terraform apply "plan.tfplan"
```

Verify cluster works: `KUBECONFIG=cluster-bootstrap/kubeconfig kubectl get ns`

Deploy Nginx Ingress Controller:
```
cd nginx-ingress-conroller
terraform init -upgrade
terraform plan -out=plan.tfplan
terraform apply "plan.tfplan"
```

Deploy nginx to test: `KUBECONFIG=cluster-bootstrap/kubeconfig kubectl apply -f nginx.yaml`

Clean-up:
```
cd nginx-ingress-conroller
terraform plan -destroy -out=plan-destroy.tfplan
terraform apply "plan-destroy.tfplan"
cd cluster-bootstrap
terraform plan -destroy -var 'my_ip=185.189.245.112/32' -var 'nodes_count=1' -out=plan-destroy.tfplan
terraform apply "plan-destroy.tfplan"
```

## Cluster with AWS IRSA for self-hosted cluster and AWS Load Balancer Controller       
You need to have installed go: https://go.dev/doc/install 

Spin-up a cluster in the same manner.

Deploy self-managed OIDC provider:
```
cd oidc-provider
terraform init -upgrade
terraform plan -target='data.kubectl_file_documents.deployment' -out=plan.tfplan # this is required to pull and template yaml provided by dev team
terraform apply "plan.tfplan"
terraform plan -out=plan.tfplan
terraform apply "plan.tfplan"
```

Deploy AWS Load Balancer Controller:
```
cd aws-lb-controller
terraform init -upgrade
terraform plan -out=plan.tfplan
terraform apply "plan.tfplan"
```

Deploy Nginx mock to test AWS LBC are able to create LB and it's accessible: `KUBECONFIG=cluster-bootstrap/kubeconfig kubectl apply -f nginx-aws-lbc.yaml`
