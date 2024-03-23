#!/usr/bin/env bash

# abort on nonzero exitstatus, unbound variable, don't hide errors within pipes, print each statement after applying all forms of substitution
set -xeuo pipefail

# kubectl cluster-info 1 > /dev/null
# cluster_init_status=$?
# if [[ $cluster_init_status == 1 ]]
# then
#     printf "Cluster is not initialized, run setup with kubeadm"
#     set -e
#     # init control plane
#     sudo kubeadm init --config /tmp/kubeadm_config.yaml
#     mkdir -p /home/ubuntu/.kube
#     sudo cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
#     sudo chown "$(id -u)":"$(id -g)" /home/ubuntu/.kube/config
#     set +e
# else
#     printf "Cluster already initialized, skip init step"
# fi

if kubectl cluster-info > /dev/null 2>&1
then
    printf "Cluster already initialized, skip init step\n"
else
        
    printf "Cluster is not initialized, run setup with kubeadm\n"
    # init control plane
    sudo kubeadm init --config /tmp/kubeadm_config.yaml
    mkdir -p /home/ubuntu/.kube
    sudo cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
    sudo chown "$(id -u)":"$(id -g)" /home/ubuntu/.kube/config
fi

i=0
while [ ${i} -le 10 ]
do
    # kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml
    # result=$?
    # if [[ $result == 0 ]]
    # then
    #     printf "Weave kubectl apply was successful"
    #     break
    # else
    #     printf "Weave kubectl apply was unsuccessful, try #%s, sleep 10 sec and re-try" "${i}"
    #     i=$(( i+1 ))
    #     sleep 10
    # fi

    if kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml
    then
        printf "Weave kubectl apply was successful\n"
        break
    else
        printf "Weave kubectl apply was unsuccessful, try #%s, sleep 10 sec and re-try\n" "${i}"
        i=$(( i+1 ))
        sleep 10
    fi

    if [ ${i} -eq 10 ]
    then
        printf "Failed to install Weave CNI\n"
        exit 1
    fi
done

# install etcdctl, if it's not
# which etcdctl
# is_etcdctl_installed=$?

# if [[ $is_etcdctl_installed == 1 ]]
# then
#     ETCD_VER=$1

#     curl -L "https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz" -o "/tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz"
#     tar xzvf "/tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz"
#     rm -f "/tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz"

#     mv "etcd-${ETCD_VER}-linux-amd64/etcdctl" /usr/local/bin
#     rm -rf "etcd-${ETCD_VER}-linux-amd64"
# fi

if which etcdctl
then
    printf "etcdctl is already installed\n"
else
    printf "Install etcdctl\n"

    # grab all tags from etcd GH repo, filter out only stable versions, get latest
    ETCD_VER=$(git ls-remote --tags --refs --sort="version:refname" --exit-code https://github.com/etcd-io/etcd.git | grep -P 'refs\/tags\/v[1-9].[1-9]{1,2}?.[1-9]{1,2}?$' | tail -1 | cut -d '/' -f 3)

    curl --silent --location "https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz" -o "/tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz"
    tar xzvf "/tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz"
    rm -f "/tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz"

    sudo mv "etcd-${ETCD_VER}-linux-amd64/etcdctl" /usr/local/bin
    rm -rf "etcd-${ETCD_VER}-linux-amd64"
fi

# add backup script to crontab to be run daily at 14:00, logs will be saved at etcd_backup.log file
sudo chmod +x /opt/etcd-backup/etcd_backup.sh
sudo chmod +x /opt/etcd-backup/etcd_restore.sh
printf "0 14 * * * ubuntu /bin/bash /opt/etcd-backup/etcd_backup.sh > /opt/etcd-backup/etcd_backup.log 2>&1\n" | sudo tee /etc/cron.d/etcd_backup

# install AWS CLI, if it's not
if which aws
then
    printf "AWS CLI is already installed\n"
else
    curl --silent --location "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    if which zip
    then
        printf "Zip is installed\n"
    else
        sudo apt install zip -y 1 > /dev/null
    fi
    unzip awscliv2.zip
    sudo ./aws/install 1 > /dev/null
    rm awscliv2.zip
    rm -rf aws
fi

if which jq
then
    printf "jq is already installed\n"
else
    sudo apt install jq -y
fi
