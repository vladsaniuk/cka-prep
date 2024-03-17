# CKA prep      
To get up and running you need to have your SSH public key available at ~/.ssh/id_rsa.pub      
You need to supply your IP, when running terraform, i.e. terraform plan -var 'my_ip=192.158.1.38/32'      
Scripts to bootstrap control plane and nodes are idempotent - they will not break anything, if run again.   
You can also provide nodes_count var to manage nodes count, default is 2, so you'll have 1 control plane and 2 nodes.     

## Backend
Backend need one-time init:
```
mv backend/versions.tf . # move S3 backend config from folder to init locally
cd backend
terraform init -upgrade
terraform plan -out=plan.tfplan
terraform apply "plan.tfplan"

mv ../versions.tf . # move back S3 backend config to move state to cloud
terraform init -upgrade
```

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
cd nginx-ingress-controller
terraform init -upgrade
terraform plan -out=plan.tfplan
terraform apply "plan.tfplan"
```

Deploy nginx to test: `KUBECONFIG=cluster-bootstrap/kubeconfig kubectl apply -f nginx.yaml`

Clean-up:
```
cd nginx-ingress-controller
terraform plan -destroy -out=plan-destroy.tfplan
terraform apply "plan-destroy.tfplan"

cd ../cluster-bootstrap
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

Clean-up:
```
cd aws-lb-controller
terraform plan -destroy -out=plan-destroy.tfplan
terraform apply "plan-destroy.tfplan"

cd ../oidc-provider
terraform plan -destroy -out=plan-destroy.tfplan
terraform apply "plan-destroy.tfplan"

cd ../cluster-bootstrap
terraform plan -destroy -var 'my_ip=185.189.245.112/32' -var 'nodes_count=1' -out=plan-destroy.tfplan
terraform apply "plan-destroy.tfplan"
```

## Access management      
You can add users and services in access-management/main.tf, you will find kubeconfig in access-management/${users|services}/kubeconfig    
For services, namespace should already exist in cluster.         
```
cd access-management
terraform init -upgrade
terraform plan -out=plan.tfplan
terraform apply "plan.tfplan"
```
Verify access works as expected
```
# service, kube-system request will fail, default namespace will work
KUBECONFIG=access-management/services/application/kubeconfig kubectl get all -n kube-system
KUBECONFIG=access-management/services/application/kubeconfig kubectl get all

# dev role, kube-system request will fail, default namespace will work
KUBECONFIG=access-management/users/jack/kubeconfig kubectl get all -n kube-system
KUBECONFIG=access-management/users/jack/kubeconfig kubectl get all

# admin role, both will work
KUBECONFIG=access-management/users/john/kubeconfig kubectl get all -n kube-system
KUBECONFIG=access-management/users/john/kubeconfig kubectl get all
```

Clean-up in the same manner, as Nginx, AWS LBC and OIDC.       

## Troubleshooting with sidecar containers
Use secrets.sh, postgres.yaml and kong-oss.yaml to spin up Kong APIGW to check how we can troubleshoot with sidecar containers.                       
k8s manifest to deploy Kong also has example of init containers:
1) Busybox to check if DB is available;
2) Kong container to run DB bootstrap;
3) another Kong container to run DB migrations, if any.

For the sake of speed and simplicity, deploy Kong to AWS LBC namespace, as it already has configured SA and IAM role to test AWS CLI commands in it's container using the same SA as AWS LBC.

secrets.sh expects 3 arguments: 1) Docker Hub username, 2) DH password or PAT, 3) k8s namespace name.

Deploy Kong: 
```
KUBECONFIG=cluster-bootstrap/kubeconfig ./secrets.sh docker_hub_username docker_hub_PAT load-balancer-controller
KUBECONFIG=cluster-bootstrap/kubeconfig kubectl apply -f postgres.yaml -n load-balancer-controller
KUBECONFIG=cluster-bootstrap/kubeconfig kubectl apply -f kong-oss.yaml -n load-balancer-controller
```

curl container:
```
KUBECONFIG=cluster-bootstrap/kubeconfig kubectl exec --stdin --tty kong-deployment-7b8c8457df-hj2qv -c troubleshooting-curl -n load-balancer-controller -- /bin/sh

# Service IP and port
~ $ curl https://10.100.106.90:8443 -k
{
  "message":"no Route matched with those values"
}

# Worker node public IP and port exposed by Service
~ $ curl https://3.239.168.148:30899 -k
{
  "message":"no Route matched with those values"
}

# Service name and port
~ $ curl https://kong-service:8443 -k
{
  "message":"no Route matched with those values"
}
```

AWS CLI container:
```
# AWS CLI get access via IRSA
KUBECONFIG=cluster-bootstrap/kubeconfig kubectl exec --stdin --tty kong-deployment-7b8c8457df-hj2qv -c troubleshooting-aws-cli -n load-balancer-controller -- /bin/bash

bash-4.2# aws acm list-certificates
{
    "CertificateSummaryList": []
}
```

Busybox container:
```
# You can manipulate files from Busybox container, as it has root access and share it with your main container
KUBECONFIG=cluster-bootstrap/kubeconfig kubectl exec --stdin --tty kong-deployment-75bb5bb58d-zdpnc -c troubleshooting-busybox -- /bin/sh
/ #
/ # whoami
root
/ # echo "test message" > /tmp/test.txt
/ # ls -l /tmp/
total 4
-rw-r--r--    1 root     root            13 Mar  9 16:40 test.txt
/ # adduser --disabled-password kong
/ # chown kong:kong /tmp/test.txt
/ # ls -l /tmp/
total 4
-rw-r--r--    1 kong     kong            13 Mar  9 16:40 test.txt
/ # exit

# We can now pick up files in Kong containers with required file permissions, as we changed ownership to kong user from inside Busybox container
KUBECONFIG=cluster-bootstrap/kubeconfig kubectl exec --stdin --tty kong-deployment-75bb5bb58d-zdpnc -- /bin/sh
Defaulted container "kong" out of: kong, troubleshooting-busybox, troubleshooting-curl, troubleshooting-aws-cli, is-db-available (init), kong-migrations-bootstrap (init), kong-migrations-up (init)
$ whoami
kong
kong@kong-deployment-75bb5bb58d-zdpnc:/$ ls -l /tmp/
total 4
-rw-r--r-- 1 kong kong 13 Mar  9 16:40 test.txt
kong@kong-deployment-75bb5bb58d-zdpnc:/$ id -u
1000
kong@kong-deployment-75bb5bb58d-zdpnc:/$ ls -ln /tmp/
total 4
-rw-r--r-- 1 1000 1000 13 Mar  9 16:40 test.txt
```

## Scheduling

nginx-aws-lbc.yaml has configured toleration to be scheduled on control plane node, hard affinity rule to be scheduled on the same node as etcd and soft anti-affinity rule for pods to be scheduled on different nodes. You can run it with:
```
KUBECONFIG=cluster-bootstrap/kubeconfig kubectl apply -f nginx-aws-lbc.yaml
KUBECONFIG=cluster-bootstrap/kubeconfig kubectl get all
```
Kong OSS has configured soft pod affinity rules to be scheduled on the same node, as PostgreSQL pod, and 1 pod per node

## Probes
Kong OSS has configured startup, readiness and liveness probes.              
Startup and liveness probes are http GET requests to Status API server, while readiness probe is TCP check on proxy https port, which is main one.
