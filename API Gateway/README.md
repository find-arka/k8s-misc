## API Gateway on an Azure Kubernetes cluster (AKS)

#### Step 1: AKS Cluster creation

Create an AKS cluster using Azure CLI from [Azure cloud shell](https://shell.azure.com).

> If you see the message `You have no storage mounted` in [Azure cloud shell](https://shell.azure.com), [this guide](https://docs.microsoft.com/en-us/azure/cloud-shell/persisting-shell-storage) should be helpful.

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
az account set --subscription $SUB_ID
az aks get-credentials --resource-group $RG --name $MY_CLUSTER_NAME --overwrite-existing
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

#### Step 2: Install gloo edge using helm

Add helm chart repository and create a K8s namespace `my-namespace` to install `gloo`.
```bash
helm repo add gloo https://storage.googleapis.com/solo-public-helm
helm repo update
kubectl create namespace my-namespace
```

Install gloo with helm
```bash
helm install gloo gloo/gloo --namespace my-namespace
```

#### Step 2: Success Criteria

- Verify that status is showing as `deployed`
```
helm -n my-namespace status gloo | grep STATUS
```
Expected output: `STATUS: deployed`

- Check all resources created in your K8s namespace
```bash
kubectl -n my-namespace get all
```
Output:
```bash
NAME                                 READY   STATUS    RESTARTS   AGE
pod/discovery-65b7df6f47-764br       1/1     Running   0          34s
pod/gateway-5685f9774f-79z5m         1/1     Running   0          34s
pod/gateway-proxy-59c76d5558-z2t75   1/1     Running   0          34s
pod/gloo-c69bb79c6-dkxbj             1/1     Running   0          34s

NAME                    TYPE           CLUSTER-IP     EXTERNAL-IP     PORT(S)                               AGE
service/gateway         ClusterIP      10.0.179.64    <none>          443/TCP                               35s
service/gateway-proxy   LoadBalancer   10.0.192.102   13.85.198.231   80:30638/TCP,443:31858/TCP            35s
service/gloo            ClusterIP      10.0.228.148   <none>          9977/TCP,9976/TCP,9988/TCP,9979/TCP   35s

NAME                            READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/discovery       1/1     1            1           35s
deployment.apps/gateway         1/1     1            1           35s
deployment.apps/gateway-proxy   1/1     1            1           35s
deployment.apps/gloo            1/1     1            1           35s

NAME                                       DESIRED   CURRENT   READY   AGE
replicaset.apps/discovery-65b7df6f47       1         1         1       35s
replicaset.apps/gateway-5685f9774f         1         1         1       35s
replicaset.apps/gateway-proxy-59c76d5558   1         1         1       35s
replicaset.apps/gloo-c69bb79c6             1         1         1       35s
```
