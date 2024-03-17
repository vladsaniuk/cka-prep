#!/usr/bin/env bash

random() {
    lenght=$1

    array=()
    for i in {a..z} {A..Z} {0..9}; 
    do
        array[$RANDOM]=$i
    done
    
    printf %s "${array[@]::$lenght}" $'\n'
}

namespace=$3
if [[ -z $namespace ]]
then
    namespace="default"
fi

kubectl create secret generic postgres-secrets \
    --from-literal=username="kong-$(random 5)" \
    --from-literal=password="$(random 32)" \
    -n $namespace

kubectl create secret docker-registry docker-hub \
    --docker-username="$1" \
    --docker-password="$2" \
    -n $namespace
