#!/usr/bin/env bash

# abort on nonzero exitstatus, unbound variable, don't hide errors within pipes, print each statement after applying all forms of substitution
set -xeuo pipefail

logger() {
    printf "%s: %s\n" "$(date "+%D %T")" "${1}\n"
}

logger "Start etcd restore"

# create restore folder
logger "Create restore folder"
restore_folder="restore-$(date +%s)"
mkdir -p "/opt/etcd-backup/${restore_folder}"

# download snapshot from S3 to local
logger "Get exact etcd backup S3 bucket name"
bucket_name=$(aws s3 ls | grep "etcd-backup" | cut -d ' ' -f 3)
logger "Download backup from S3 bucket ${bucket_name}"
aws s3 cp "s3://${bucket_name}/etcd_backup.db" "/opt/etcd-backup/${restore_folder}"

# restore data 
logger "Restore data into /opt/etcd-backup/${restore_folder} folder"
ETCDCTL_API=3 etcdctl snapshot restore "/opt/etcd-backup/${restore_folder}/etcd_backup.db" \
    --data-dir "/opt/etcd-backup/${restore_folder}/data"

# grab current etcd data directory 
logger "Get current etcd data directory from static pod"
etcd_pod_name="etcd-$(hostname)"
data_curr_dir=$(kubectl get pod "${etcd_pod_name}" -n kube-system -o json | jq --raw-output '.spec.volumes[] | select(.name == "etcd-data") | .hostPath.path')
# replace current data dir to new in etcd static pod manifest, but first escape slash in current data directory path
escaped_data_curr_dir=$(echo "${data_curr_dir}" | sed 's/\//\\\//g')
logger "Replace current etcd data directory with new one"
sudo sed -i "s/path: ${escaped_data_curr_dir}/path: \/opt\/etcd-backup\/${restore_folder}\/data/" /etc/kubernetes/manifests/etcd.yaml
