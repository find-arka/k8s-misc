# k8s-misc
Notes from miscellaneous K8s learning experiences

> NOTE: This is strictly WIP documentation from my personal experience, if you are following this, and creating resources on public cloud, please be mindful and clean up to avoid unnecessary bills.

## API Gateway on a K8s cluster
### Step 1: AKS Cluster creation
```bash
# Setup variables for ease and readability of the future commands
LOCATION=$(az group list | jq -r '.[].location')
RG=$(az group list | jq -r '.[].name')
MY_CLUSTER_NAME=myAKSCluster

# Print Intent 
echo "Planning to create a new AKS cluster with name '$MY_CLUSTER_NAME' in Resource Group '$RG' at '$LOCATION'. Subscription ID is '$SUB_ID'"

##
# Create a multinode (3 nodes) K8s cluster spread out in 3 AZs
# Also generate SSH public and private key files if missing. They could be used to SSH into the VMs
##
az aks create \
    --resource-group $RG \
    --name $MY_CLUSTER_NAME \
    --generate-ssh-keys \
    --node-count 3 \
    --zones 1 2 3 \
    --nodepool-name infra \
    --nodepool-tags node-type=infra

# Get admin access credentials for the managed Kubernetes cluster
az aks get-credentials --resource-group $RG --name $MY_CLUSTER_NAME --admin 

# If `az aks get-credentials` fails, you would have to manually invoke these commands and re-run the get-credentials command
# SUB_ID=$(az account subscription list | jq -r .[].subscriptionId)
# az aks get-credentials --resource-group $RG --name $MY_CLUSTER_NAME --overwrite-existing --admin
```
### Step 1 Success Criteria
- 3 nodes, each in different AZs should be created.
- The nodes should have labels to imply that they are part of `infra` nodepool.
```
$ kubectl get nodes -L agentpool,topology.kubernetes.io/zone
NAME                            STATUS   ROLES   AGE   VERSION   AGENTPOOL   ZONE
aks-infra-28829824-vmss000000   Ready    agent   30m   v1.22.6   infra       southcentralus-1
aks-infra-28829824-vmss000001   Ready    agent   30m   v1.22.6   infra       southcentralus-2
aks-infra-28829824-vmss000002   Ready    agent   30m   v1.22.6   infra       southcentralus-3
```
