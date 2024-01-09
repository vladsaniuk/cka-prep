#!/bin/bash

ls /etc/kubernetes/kubelet.conf
node_init_status=$?
if [[ $node_init_status == 0 ]]
then
    echo "Node already joined the cluster, skip join step"
else 
    sudo bash /tmp/node_join.sh
fi