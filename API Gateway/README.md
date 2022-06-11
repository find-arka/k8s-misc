## API Gateway on a K8s cluster

#### Step 1: AKS Cluster creation

Create an AKS cluster using Azure CLI from [Azure cloud shell](https://shell.azure.com).
> If you are seeing the message `You have no storage mounted`, [this guide](https://docs.microsoft.com/en-us/azure/cloud-shell/persisting-shell-storage) might be helpful to setup storage.

- Setup variables for ease and readability of the future commands
```bash 
LOCATION=$(az group list | jq -r '.[].location')
RG=$(az group list | jq -r '.[].name')
MY_CLUSTER_NAME=myAKSCluster

# Intent 
echo "Planning to create a new multinode AKS cluster with name '$MY_CLUSTER_NAME' in Resource Group '$RG' at '$LOCATION'."
```

- Create a multinode K8s cluster spread out in different AZs.
```bash
az aks create \
    --resource-group $RG \
    --name $MY_CLUSTER_NAME \
    --generate-ssh-keys \
    --node-count 2 \
    --zones 1 2 \
    --nodepool-name infra \
    --nodepool-tags node-type=infra
```

- Get access credentials for the managed Kubernetes cluster
```bash
az aks get-credentials --resource-group $RG --name $MY_CLUSTER_NAME 
```

- If the above `az aks get-credentials` fails, you would have to manually invoke these commands and re-run the get-credentials command
```bash
SUB_ID=$(az account subscription list | jq -r .[].subscriptionId)
az aks get-credentials --resource-group $RG --name $MY_CLUSTER_NAME --overwrite-existing --admin
```

#### Step 1: Success Criteria

- Multinode cluster, each nod in different Availability zone should be created.
- The nodes should have labels to imply that they are part of `infra` nodepool.

Verification:
```bash
kubectl get nodes -L agentpool,topology.kubernetes.io/zone
```

Sample Output:
```bash
NAME                            STATUS   ROLES   AGE   VERSION   AGENTPOOL   ZONE
aks-infra-28829824-vmss000000   Ready    agent   30m   v1.22.6   infra       southcentralus-1
aks-infra-28829824-vmss000001   Ready    agent   30m   v1.22.6   infra       southcentralus-2
```
