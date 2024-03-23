#!/usr/bin/env bash

# abort on nonzero exitstatus, unbound variable, don't hide errors within pipes, print each statement after applying all forms of substitution
set -xeuo pipefail

random() {
    lenght=$1

    array=()
    for i in {a..z} {A..Z} {0..9}; 
    do
        array[$RANDOM]=$i
    done
    
    printf %s "${array[@]::${lenght}}" $'\n'
}

namespace=$3
if [[ -z $namespace ]]
then
    namespace="default"
fi

printf "We setup secrets here and we we'll not print them\n"
set +x

kubectl create secret generic postgres-secrets \
    --from-literal=username="kong-$(random 5)" \
    --from-literal=password="$(random 32)" \
    -n $namespace

kubectl create secret docker-registry docker-hub \
    --docker-username="$1" \
    --docker-password="$2" \
    -n $namespace
