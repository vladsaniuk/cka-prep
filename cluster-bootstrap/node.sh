#!/usr/bin/env bash

# abort on nonzero exitstatus, unbound variable, don't hide errors within pipes, print each statement after applying all forms of substitution
set -xeuo pipefail

if ls /etc/kubernetes/kubelet.conf
then
    printf "Node already joined the cluster, skip join step\n"
else 
    sudo bash /tmp/node_join.sh
fi
