# CKA prep      
To get up and running you need to have your SSH public key available at ~/.ssh/id_rsa.pub      
You need to supply your IP, when running terraform, i.e. terraform plan -var 'my_ip=192.158.1.38/32'      
Scripts to bootstrap control plane and nodes are idempotent - they will not break anything, if run again.   
You can also provide nodes_count var to manage nodes count, default is 2, so you'll have 1 control plane and 2 nodes.     