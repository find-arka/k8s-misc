# Gloo Edge - Azure Kubernetes Services (AKS)

## Step 1: AKS Cluster creation

Create an AKS cluster using Azure CLI from [Azure cloud shell](https://shell.azure.com).

> If you see the message `You have no storage mounted` in Azure cloud shell, [this guide](https://docs.microsoft.com/en-us/azure/cloud-shell/persisting-shell-storage) should be helpful.

- Setup variables for ease and readability of the future commands

If you already have a test Resource Group created in Azure-
```bash
LOCATION=$(az group list | jq -r '.[].location')
RG=$(az group list | jq -r '.[].name')
MY_CLUSTER_NAME="myAKSCluster"

# Intent 
echo "Planning to create a new multinode AKS cluster with name '$MY_CLUSTER_NAME' in Resource Group '$RG' at '$LOCATION'."
```

If you need to create a new Resource Group in a dedicated region e.g. southcentralus- 
```bash
LOCATION="southcentralus"
RG="my-aks-cluster-rg"
MY_CLUSTER_NAME="myAKSCluster"
az group create --location $LOCATION \
                --name $RG;
# Intent 
echo "Planning to create a new multinode AKS cluster with name '$MY_CLUSTER_NAME' in Resource Group '$RG' at '$LOCATION'."
```
- Create a multinode K8s cluster spread out in different AZs with nodepool name: `infra`. This nodepool is meant for core infrastructure component deployment.
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

- Add a different nodepool with tag `app` for applications which are not infrastructure related. This nodepool could be configured to be elastic in nature and end users could deploy their applications in this nodepool. For simplicity, I have kept the node count to 1 for now.
```
az aks nodepool add \
  --resource-group $RG \
  --cluster-name $MY_CLUSTER_NAME \
  --nodepool-name app \
  --tags node-type=app \
  --node-count 1
```

- Get access credentials for the managed Kubernetes cluster
```bash
az aks get-credentials --resource-group $RG --name $MY_CLUSTER_NAME --overwrite-existing
```

#### Step 1: Success Criteria

- Multinode cluster, each node in different Availability Zone should be created.
- The nodes should have labels to imply that they are part of which nodepool.

Verification:
```bash
kubectl get nodes -L agentpool,topology.kubernetes.io/zone
```

Sample Output:
```bash
NAME                            STATUS   ROLES   AGE   VERSION   AGENTPOOL   ZONE
aks-app-13271860-vmss000000     Ready    agent   12s   v1.22.6   app         
aks-infra-11482989-vmss000000   Ready    agent   14m   v1.22.6   infra       centralus-1
aks-infra-11482989-vmss000001   Ready    agent   14m   v1.22.6   infra       centralus-2
```

## Step 2: Install Gloo Edge using helm

> Documentation of Gloo Edge helm chart customization options is present [here](https://docs.solo.io/gloo-edge/latest/reference/helm_chart_values/open_source_helm_chart_values/)

- Add helm chart repository and create a K8s namespace `gloo-system` to install `gloo`.
```bash
helm repo add gloo https://storage.googleapis.com/solo-public-helm
helm repo update
kubectl create namespace gloo-system
```

- Create an override file with `antiAffinity`, `nodeSelector` and upgraded `replicaCount` for Gateway Proxy component.
> Similar config could be introduced to the other Gloo components via the helm chart configuration options present [here](https://docs.solo.io/gloo-edge/latest/reference/helm_chart_values/open_source_helm_chart_values/)
```yaml
cat > gloo-value-overrides.yaml - <<EOF
gatewayProxies:
  gatewayProxy:
    kind:
      deployment:
        replicas: 2
    antiAffinity: true
    podTemplate:
      nodeSelector:
        agentpool: 'infra'
EOF
```

- Verify that the override config generates the desired template
```bash
helm template -f gloo-value-overrides.yaml --namespace gloo-system gloo gloo/gloo
```

- install with the overrides
```bash
helm install -f gloo-value-overrides.yaml --namespace gloo-system gloo gloo/gloo
```

#### Step 2: Success Criteria

- Verify that status is showing as `deployed`
```
helm -n gloo-system status gloo | grep STATUS
```
Expected output: `STATUS: deployed`

- Verify that the Gateway Proxy nodes are indeed running in different nodes
```bash
kubectl -n gloo-system get pods -l gloo=gateway-proxy -o wide
```

Inspect the `NODE` column in the output-
```bash
NAME                             READY   STATUS    RESTARTS   AGE     IP            NODE                            NOMINATED NODE   READINESS GATES
gateway-proxy-6857ff4f68-rbnck   1/1     Running   0          5m56s   10.244.0.10   aks-infra-33378480-vmss000000   <none>           <none>
gateway-proxy-6857ff4f68-s7bj7   1/1     Running   0          5m56s   10.244.1.10   aks-infra-33378480-vmss000001   <none>           <none>
```

- Check all resources created in your K8s namespace
```bash
kubectl -n gloo-system get all
```
Output:
```bash
NAME                                 READY   STATUS    RESTARTS   AGE
pod/discovery-65b7df6f47-w68jc       1/1     Running   0          4m38s
pod/gateway-5685f9774f-6hhwg         1/1     Running   0          4m38s
pod/gateway-proxy-6857ff4f68-rbnck   1/1     Running   0          4m38s
pod/gateway-proxy-6857ff4f68-s7bj7   1/1     Running   0          4m38s
pod/gloo-c69bb79c6-m2khh             1/1     Running   0          4m38s

NAME                    TYPE           CLUSTER-IP     EXTERNAL-IP     PORT(S)                               AGE
service/gateway         ClusterIP      10.0.153.111   <none>          443/TCP                               4m38s
service/gateway-proxy   LoadBalancer   10.0.18.15     20.84.225.139   80:32584/TCP,443:30740/TCP            4m38s
service/gloo            ClusterIP      10.0.248.81    <none>          9977/TCP,9976/TCP,9988/TCP,9979/TCP   4m38s

NAME                            READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/discovery       1/1     1            1           4m39s
deployment.apps/gateway         1/1     1            1           4m39s
deployment.apps/gateway-proxy   2/2     2            2           4m39s
deployment.apps/gloo            1/1     1            1           4m39s

NAME                                       DESIRED   CURRENT   READY   AGE
replicaset.apps/discovery-65b7df6f47       1         1         1       4m39s
replicaset.apps/gateway-5685f9774f         1         1         1       4m39s
replicaset.apps/gateway-proxy-6857ff4f68   2         2         2       4m39s
replicaset.apps/gloo-c69bb79c6             1         1         1       4m39s
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
