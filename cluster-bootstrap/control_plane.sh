#!/bin/bash

kubectl cluster-info 1 > /dev/null
cluster_init_status=$?
if [[ $cluster_init_status == 1 ]]
then
    echo "Cluster is not initialized, run setup with kubeadm"
    set -e
    # init control plane
    sudo kubeadm init --config /tmp/kubeadm_config.yaml
    mkdir -p /home/ubuntu/.kube
    sudo cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
    sudo chown "$(id -u)":"$(id -g)" /home/ubuntu/.kube/config
    set +e
else
    echo "Cluster already initialized, skip init step"
fi

i=0
while [ $i -le 10 ]
do
    kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml
    result=$?
    if [[ $result == 0 ]]
    then
        echo "Weave kubectl apply was successful"
        break
    else
        echo "Weave kubectl apply was unsuccessful, try #$i, sleep 10 sec and re-try"
        i=$(( i+1 ))
        sleep 10
    fi
done