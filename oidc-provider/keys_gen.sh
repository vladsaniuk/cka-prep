#!/bin/bash

# convert the SSH pubkey to PKCS8
ssh-keygen -e -m PKCS8 -f ../cluster-bootstrap/sa-signer.key.pub > sa-signer-pkcs8.pub

go run ./hack/self-hosted/main.go -key sa-signer-pkcs8.pub  | jq '.keys += [.keys[0]] | .keys[1].kid = ""' > keys.json