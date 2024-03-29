#!/usr/bin/env bash

# abort on nonzero exitstatus, unbound variable, don't hide errors within pipes, print each statement after applying all forms of substitution
set -xeuo pipefail

# disable swap
swapoff -a

# forwarding IPv4 and letting iptables see bridged traffic
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system
lsmod | grep br_netfilter
lsmod | grep overlay

# install and configure CRI, containerd
apt-get update
apt-get install -y containerd
mkdir /etc/containerd
containerd config default | tee /etc/containerd/config.toml
systemctl restart containerd
systemctl status containerd --no-pager

#  install kubelet, kubeadm, kubectl v1.25
apt-get install -y apt-transport-https ca-certificates curl gpg
mkdir -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.25/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
printf 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.25/deb/ /\n' | tee /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# set hostname to DNS record - AWS Cloud Provider (Cloud Controller Manager) pre-requisite 
hostnamectl set-hostname "$(curl -s http://169.254.169.254/latest/meta-data/local-hostname)"

# grab instance type
instanceType=$(curl -s http://169.254.169.254/latest/meta-data/instance-type)

# set extra arg for Kubelet, this is to push it to pick up external cloud provider, required for AWS Cloud Provider
printf "KUBELET_EXTRA_ARGS=--cloud-provider external --node-labels=instance-type=%s\n" "${instanceType}" | tee /etc/default/kubelet
