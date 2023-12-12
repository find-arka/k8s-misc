## Prerequisite setup

### Created config namespaces in mgmt cluster

```bash
kubectl --context arka-ocp-mgmt-cluster create namespace "platform-core-config";
kubectl --context arka-ocp-mgmt-cluster create namespace "frontend-config";
```

### app namespace creation (will deploy nginx-a , nginx-b here)
```bash
kubectl --context arka-ocp-workload-cluster-1 create namespace "frontend-ns-1";
kubectl --context arka-ocp-workload-cluster-2 create namespace "frontend-ns-1";
```

### ready to inject sidecars
```bash
kubectl --context arka-ocp-workload-cluster-1 label namespace "frontend-ns-1" istio-injection=enabled --overwrite;
kubectl --context arka-ocp-workload-cluster-2 label namespace "frontend-ns-1" istio-injection=enabled --overwrite;
```

### add-scc-to-group, NetworkAttachmentDefinition creation for app Namespace
```bash
for CURRENT_CONTEXT in arka-ocp-workload-cluster-1 arka-ocp-workload-cluster-2
do
oc --context "${CURRENT_CONTEXT}" adm policy add-scc-to-group anyuid "system:serviceaccounts:frontend-ns-1"

cat <<EOF | oc --context "${CURRENT_CONTEXT}" -n frontend-ns-1 create -f -
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: istio-cni
EOF
done
```

## Gloo Mesh Workspace, WorkspaceSettings config

### platform-core-ws (istio-gateways are part of this workspace)
```bash
kubectl apply --context arka-ocp-mgmt-cluster -f- <<EOF
apiVersion: admin.gloo.solo.io/v2
kind: Workspace
metadata:
  name: platform-core-ws
  namespace: gloo-mesh
spec:
  workloadClusters:
# ------------ gm config ns ------------
  - name: arka-ocp-mgmt-cluster
    namespaces:
    - name: platform-core-config
    configEnabled: true
# --------------------------------------
  - name: arka-ocp-workload-cluster-1
    namespaces:
    - name: 'istio-gateways'
    configEnabled: false
  - name: arka-ocp-workload-cluster-2
    namespaces:
    - name: 'istio-gateways'
    configEnabled: false
---
apiVersion: admin.gloo.solo.io/v2
kind: WorkspaceSettings
metadata:
  name: platform-core-ws
  namespace: platform-core-config
spec:
  importFrom:
  - workspaces:
    - name: "*"
  exportTo:
  - workspaces:
    - name: "*"
    resources:
    - kind: SERVICE
  options:
    federation:
      enabled: false
    serviceIsolation:
      enabled: true
      trimProxyConfig: true
EOF
```

### frontend-ws ( nginx a, nginx b are part of this )
```bash
kubectl apply --context arka-ocp-mgmt-cluster -f- <<EOF
apiVersion: admin.gloo.solo.io/v2
kind: Workspace
metadata:
  name: frontend-ws
  namespace: gloo-mesh
spec:
  workloadClusters:
# ------------ gm config ns ------------
  - name: arka-ocp-mgmt-cluster
    namespaces:
    - name: frontend-config
    configEnabled: true
# --------------------------------------
  - name: arka-ocp-workload-cluster-1
    namespaces:
    - name: 'frontend-ns-1'
    configEnabled: false
  - name: arka-ocp-workload-cluster-2
    namespaces:
    - name: 'frontend-ns-1'
    configEnabled: false
---
apiVersion: admin.gloo.solo.io/v2
kind: WorkspaceSettings
metadata:
  name: frontend-ws
  namespace: frontend-config
spec:
  exportTo:
  - workspaces:
    - name: platform-core-ws
    resources:
    - kind: SERVICE
    - kind: ROUTE_TABLE
  options:
    federation:
      enabled: false
    serviceIsolation:
      enabled: true
      trimProxyConfig: true
EOF
```


## Deploy apps

### Deploy nginx a and nginx b
```bash
for CURRENT_CONTEXT in arka-ocp-workload-cluster-1 arka-ocp-workload-cluster-2
do
kubectl apply --context ${CURRENT_CONTEXT} -f- <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nginx
  namespace: frontend-ns-1
  labels:
    account: nginx
---
apiVersion: v1
kind: Service
metadata:
  name: nginx
  namespace: frontend-ns-1
  labels:
    app: nginx
spec:
  selector:
    app: nginx
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 80
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: index-html-configmap-a
  namespace: frontend-ns-1
data:
  index.html: |
    <html>
    <h1>Welcome to nginx!</h1>
    </br>
    <h1> Cluster: ${CURRENT_CONTEXT} </h1>
    <h1> instance: a </h1>
    </html>
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment-a
  namespace: frontend-ns-1
spec:
  selector:
    matchLabels:
      app: nginx
      instance: a
  replicas: 1
  template:
    metadata:
      labels:
        app: nginx
        instance: a
    spec:
      serviceAccount: nginx
      serviceAccountName: nginx
      containers:
      - name: nginx
        image: nginx:1.14.2
        ports:
        - containerPort: 80
        volumeMounts:
        - name: nginx-index-file
          mountPath: /usr/share/nginx/html/
      volumes:
      - name: nginx-index-file
        configMap:
          name: index-html-configmap-a
EOF

kubectl apply --context ${CURRENT_CONTEXT} -f- <<EOF
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: index-html-configmap-b
  namespace: frontend-ns-1
data:
  index.html: |
    <html>
    <h1>Welcome to nginx!</h1>
    </br>
    <h1> Cluster: ${CURRENT_CONTEXT} </h1>
    <h1> instance: b </h1>
    </html>
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment-b
  namespace: frontend-ns-1
spec:
  selector:
    matchLabels:
      app: nginx
      instance: b
  replicas: 1
  template:
    metadata:
      labels:
        app: nginx
        instance: b
    spec:
      serviceAccount: nginx
      serviceAccountName: nginx
      containers:
      - name: nginx
        image: nginx:1.14.2
        ports:
        - containerPort: 80
        volumeMounts:
        - name: nginx-index-file
          mountPath: /usr/share/nginx/html/
      volumes:
      - name: nginx-index-file
        configMap:
          name: index-html-configmap-b
EOF

kubectl --context ${CURRENT_CONTEXT} rollout status -n frontend-ns-1 deploy/nginx-deployment-b
kubectl --context ${CURRENT_CONTEXT} rollout status -n frontend-ns-1 deploy/nginx-deployment-a
done
```



## Create Gloo Mesh VirtualGateway, RouteTable to setup North-South traffic

### VirtualGateway
```bash
kubectl --context arka-ocp-mgmt-cluster apply -f - <<EOF
apiVersion: networking.gloo.solo.io/v2
kind: VirtualGateway
metadata:
  name: north-south-gw-nginx
  namespace: platform-core-config
spec:
  workloads:
    - selector:
        labels:
          istio: ingressgateway
          app: istio-ingressgateway
        cluster: arka-ocp-workload-cluster-1
  listeners: 
    - http: {}
      port:
        number: 80
      allowedRouteTables:
        - host: 'nginx.frontend-ns-1.svc.cluster.local'
EOF
```

### RouteTable

```bash
kubectl --context arka-ocp-mgmt-cluster apply -f - <<EOF
apiVersion: networking.gloo.solo.io/v2
kind: RouteTable
metadata:
  name: ingress-to-nginx
  namespace: frontend-config
spec:
  hosts:
    - 'nginx.frontend-ns-1.svc.cluster.local'
  virtualGateways:
    - name: north-south-gw-nginx
      namespace: platform-core-config
      cluster: arka-ocp-mgmt-cluster
  workloadSelectors: []
  http:
    - name: ingress-to-nginx-route
      matchers:
      - uri:
          prefix: /
      forwardTo:
        destinations:
          - kind: SERVICE
            ref:
              name: nginx
              namespace: frontend-ns-1
              cluster: arka-ocp-workload-cluster-1
            port:
              number: 80
EOF
```

## Create LoadBalancerPolicy with consistentHash on header

```bash
kubectl --context arka-ocp-mgmt-cluster apply -f - << EOF
apiVersion: trafficcontrol.policy.gloo.solo.io/v2
kind: LoadBalancerPolicy
metadata:
  name: sticky-nginx-loadbalancer-policy-ingress
  namespace: platform-core-config
spec:
  applyToDestinations:
    - kind: SERVICE
      selector:  
        cluster: arka-ocp-workload-cluster-1
        name: nginx
        namespace: frontend-ns-1
      port:
        number: 80
  config:
    consistentHash:
      httpHeaderName: x-user
EOF
```

### Generated DestinationRule

```bash
kubectl --context arka-ocp-workload-cluster-1 get destinationrule \
-n istio-gateways \
-l gloo.solo.io/parent_name=nginx \
-l gloo.solo.io/parent_kind=Service -o yaml
```

```yaml
apiVersion: v1
items:
- apiVersion: networking.istio.io/v1beta1
  kind: DestinationRule
  metadata:
    annotations:
      cluster.solo.io/cluster: arka-ocp-workload-cluster-1
    creationTimestamp: "2023-12-11T19:09:57Z"
    generation: 1
    labels:
      agent.gloo.solo.io: gloo-mesh
      cluster.multicluster.solo.io: arka-ocp-workload-cluster-1
      context.mesh.gloo.solo.io/cluster: arka-ocp-workload-cluster-1
      context.mesh.gloo.solo.io/namespace: istio-gateways
      context.mesh.gloo.solo.io/workspace: platform-core-ws
      gloo.solo.io/parent_cluster: arka-ocp-workload-cluster-1
      gloo.solo.io/parent_group: ""
      gloo.solo.io/parent_kind: Service
      gloo.solo.io/parent_name: nginx
      gloo.solo.io/parent_namespace: frontend-ns-1
      gloo.solo.io/parent_version: v1
      owner.gloo.solo.io/name: gloo-mesh
      reconciler.mesh.gloo.solo.io/name: translator
      relay.solo.io/cluster: arka-ocp-workload-cluster-1
    name: nginx-frontend-ns-1-svc-cluster-e860c5ab270c786357e08ef1008a449
    namespace: istio-gateways
    resourceVersion: "149927"
    uid: 31e6424a-f89e-410f-a369-865d4c4812c2
  spec:
    exportTo:
    - .
    host: nginx.frontend-ns-1.svc.cluster.local
    trafficPolicy:
      portLevelSettings:
      - loadBalancer:
          consistentHash:
            httpHeaderName: x-user
        port:
          number: 80
kind: List
metadata:
  resourceVersion: ""
```

## Test access

### test access with header "x-user: arka"

```bash
rm -rf ~/all-nginx-hits.txt
ENDPOINT_HTTP_GW_CLUSTER1=$(kubectl --context arka-ocp-workload-cluster-1 -n istio-gateways get svc istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].*}'):80
for i in {1..50}
do
  echo; echo "Attempt #${i}";echo;
  OUTPUT=$(curl -s -H "x-user: arka" -H "host: nginx.frontend-ns-1.svc.cluster.local" "http://${ENDPOINT_HTTP_GW_CLUSTER1}/")
  echo $OUTPUT
  echo $OUTPUT | grep -A1 "Cluster" >> ~/all-nginx-hits.txt
done

INSTANCE_A_COUNT=$(cat ~/all-nginx-hits.txt | grep 'instance: a' | wc -l)
INSTANCE_B_COUNT=$(cat ~/all-nginx-hits.txt | grep 'instance: b' | wc -l)

echo; echo "#############################################################################"
echo "Expectation - Traffic should be only going to either instance a or instance b. Not to both."
echo "#############################################################################"
echo; echo "--Output--"
echo; echo "nginx instance a hits: $INSTANCE_A_COUNT"
echo; echo "nginx instance b hits: $INSTANCE_B_COUNT"
rm -rf ~/all-nginx-hits.txt

if [ ${INSTANCE_A_COUNT} -gt 0 ] && [ ${INSTANCE_B_COUNT} -gt 0 ]; then
    echo; echo "#############################################################################"
    echo "Test failure";
    echo "#############################################################################"
else
    echo; echo "#############################################################################"
    echo "Test success";
    echo "#############################################################################"
fi
```

### test access with header "x-user: tata"

```bash
rm -rf ~/all-nginx-hits-window-2.txt
ENDPOINT_HTTP_GW_CLUSTER1=$(kubectl --context arka-ocp-workload-cluster-1 -n istio-gateways get svc istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].*}'):80
for i in {1..50}
do
  echo; echo "Attempt #${i}";echo;
  OUTPUT=$(curl -s -H "x-user: tata" -H "host: nginx.frontend-ns-1.svc.cluster.local" "http://${ENDPOINT_HTTP_GW_CLUSTER1}/")
  echo $OUTPUT
  echo $OUTPUT | grep -A1 "Cluster" >> ~/all-nginx-hits-window-2.txt
done

INSTANCE_A_COUNT=$(cat ~/all-nginx-hits-window-2.txt | grep 'instance: a' | wc -l)
INSTANCE_B_COUNT=$(cat ~/all-nginx-hits-window-2.txt | grep 'instance: b' | wc -l)

echo; echo "#############################################################################"
echo "Expectation - Traffic should be only going to either instance a or instance b. Not to both."
echo "#############################################################################"
echo; echo "--Output--"
echo; echo "nginx instance a hits: $INSTANCE_A_COUNT"
echo; echo "nginx instance b hits: $INSTANCE_B_COUNT"
rm -rf ~/all-nginx-hits-window-2.txt

if [ ${INSTANCE_A_COUNT} -gt 0 ] && [ ${INSTANCE_B_COUNT} -gt 0 ]; then
    echo; echo "#############################################################################"
    echo "Test failure";
    echo "#############################################################################"
else
    echo; echo "#############################################################################"
    echo "Test success";
    echo "#############################################################################"
fi
```

### Output summary

#### for "x-user: arka"
```bash
#############################################################################
Expectation - Traffic should be only going to either instance a or instance b. Not to both.
#############################################################################

--Output--

nginx instance a hits:       50

nginx instance b hits:        0

#############################################################################
Test success
#############################################################################
```

#### for "x-user: tata"
```bash
#############################################################################
Expectation - Traffic should be only going to either instance a or instance b. Not to both.
#############################################################################

--Output--

nginx instance a hits:        0

nginx instance b hits:       50

#############################################################################
Test success
#############################################################################
```
