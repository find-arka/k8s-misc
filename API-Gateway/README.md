# Gloo Edge - Azure Kubernetes Services (AKS)

## Step 1: AKS Cluster creation

Create an AKS cluster using Azure CLI from [Azure cloud shell](https://shell.azure.com).

> If you see the message `You have no storage mounted` in Azure cloud shell, [this guide](https://docs.microsoft.com/en-us/azure/cloud-shell/persisting-shell-storage) should be helpful.

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

## Step 2: Install Gloo Edge using helm

> Documentation of Gloo Edge helm chart customization options is present [here](https://docs.solo.io/gloo-edge/latest/reference/helm_chart_values/open_source_helm_chart_values/)

- Add helm chart repository and create a K8s namespace `gloo-system` to install `gloo`.
```bash
helm repo add gloo https://storage.googleapis.com/solo-public-helm
helm repo update
kubectl create namespace gloo-system
```

- Install gloo with helm
```bash
helm install gloo gloo/gloo --namespace gloo-system
```

#### Step 2: Success Criteria

- Verify that status is showing as `deployed`
```
helm -n gloo-system status gloo | grep STATUS
```
Expected output: `STATUS: deployed`

- Check all resources created in your K8s namespace
```bash
kubectl -n gloo-system get all
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

#### glooctl (optional CLI tool which assists in operations)

- Installation:
```bash
curl -sL https://run.solo.io/gloo/install | sh
export PATH=$HOME/.gloo/bin:$PATH
```

- Debugging usage:
```bash
glooctl check
```

- Check upstreams:
```bash
glooctl get upstreams
```

# Next Steps

1. [Setup observability components](https://github.com/find-arka/k8s-misc/blob/main/API-Gateway/setup-observability.md)
2. [Setup sample application and explore API Gateway features](https://github.com/find-arka/k8s-misc/blob/main/API-Gateway/test-with-sample-application.md)
