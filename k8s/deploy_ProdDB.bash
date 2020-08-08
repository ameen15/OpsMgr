#!/bin/bash

d=$( dirname "$0" )
cd "${d}"
PATH=$PATH:"${d}"/Misc

source init.conf

# clean up any previous certs and services
kubectl delete secret my-replica-set-cert > /dev/null 2>&1

kubectl delete csr my-replica-set-0.mongodb > /dev/null 2>&1
kubectl delete csr my-replica-set-1.mongodb > /dev/null 2>&1
kubectl delete csr my-replica-set-2.mongodb > /dev/null 2>&1

kubectl delete svc my-replica-set-0 > /dev/null 2>&1
kubectl delete svc my-replica-set-1 > /dev/null 2>&1
kubectl delete svc my-replica-set-2 > /dev/null 2>&1

# clean out any old horizon from the config
#sed -i .bak -e '/horizon/d' -e '/connectivity:/d' -e '/replicaSetHorizons:/d' ops-mgr-resource-my-replica-set-secure-auth.yaml

# Create map for OM and the Org/Project
if [[ ${tls} == 1 ]]
then
kubectl delete configmap my-replica-set > /dev/null 2>&1
kubectl create configmap my-replica-set \
  --from-literal="baseUrl=${opsMgrUrl}" \
  --from-literal="projectName=MyReplicaSet" \
  --from-literal="sslMMSCAConfigMap=opsmanager-cert-ca" \
  --from-literal="sslRequireValidMMSServerCertificates=‘true’"
else
kubectl delete configmap my-replica-set > /dev/null 2>&1
kubectl create configmap my-replica-set \
  --from-literal="baseUrl=${opsMgrUrl}" \
  --from-literal="projectName=MyReplicaSet"
fi
   # --from-literal="orgId={$orgId}>" #Optional

# # Create a secret for the member certs for TLS
# kubectl delete secret         my-replica-set-cert > /dev/null 2>&1
# kubectl create secret generic my-replica-set-cert \
#   --from-file=my-replica-set-0-pem \
#   --from-file=my-replica-set-1-pem \
#   --from-file=my-replica-set-2-pem
# # Create a map for the cert
# kubectl delete configmap ca-pem > /dev/null 2>&1
# kubectl create configmap ca-pem --from-file=ca-pem

# Create a a secret for db user credentials
kubectl delete secret dbadmin-credentials > /dev/null 2>&1
kubectl create secret generic dbadmin-credentials \
  --from-literal=name="${dbadmin}" \
  --from-literal=password="${dbpassword}"

# Create the User Resource
kubectl apply -f ops-mgr-resource-database-user-conf.yaml

# Create the DB Resource
#kubectl apply -f ops-mgr-resource-my-replica-set.yaml
#kubectl apply -f ops-mgr-resource-my-replica-set-secure.yaml
kubectl apply -f ops-mgr-resource-my-replica-set-secure-auth.yaml

# Monitor the progress
notapproved="Not all certificates have been approved"
certificate="Certificate"
while true
do
    kubectl get mongodb/my-replica-set
    eval status=$( kubectl get mongodb/my-replica-set -o json| jq '.status.phase' )
    eval message=$( kubectl get mongodb/my-replica-set -o json| jq '.status.message')
    printf "%s\n" "$message"
    if [[ "${message:0:39}" == "${notapproved}" ||  "${message:0:11}" == "${certificate}" ]]
    then
        # TLS Cert approval (if using autogenerated certs -- depricated)
        kubectl certificate approve my-replica-set-0.mongodb 
        kubectl certificate approve my-replica-set-1.mongodb
        kubectl certificate approve my-replica-set-2.mongodb
    fi
    #if [[ $status == "Pending" || $status == "Running" ]];
    if [[ "$status" == "Running" ]];
    then
        printf "%s\n" "$status"
        break
    fi
    sleep 15
done

printf "\n"
printf "%s\n" "Wait a minute for the reconfiguration and then connect by running: Misc/kub_connect_to_my-replica-set.bash"
printf "\n"

exit 0
