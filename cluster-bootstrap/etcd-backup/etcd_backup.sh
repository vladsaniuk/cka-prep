#!/usr/bin/env bash

# abort on nonzero exitstatus, unbound variable, don't hide errors within pipes, print each statement after applying all forms of substitution
set -xeuo pipefail

logger() {
    printf "%s: %s\n" "$(date "+%D %T")" "${1}"
}

logger "Start etcd backup"

logger "Create snapshot"
sudo ETCDCTL_API=3 etcdctl snapshot save /opt/etcd-backup/etcd_backup.db \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key

logger "Get exact etcd backup S3 bucket name"
bucket_name=$(/usr/local/bin/aws s3 ls | grep "etcd-backup" | cut -d ' ' -f 3)

logger "Upload backup to S3 bucket ${bucket_name}"
sudo /usr/local/bin/aws s3 cp /opt/etcd-backup/etcd_backup.db "s3://${bucket_name}" --sse aws:kms
