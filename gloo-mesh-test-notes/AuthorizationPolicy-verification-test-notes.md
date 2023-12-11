We have 2 `Namespace` and 2 corresponding `Workspace` objects:
1. client-namespace (`curlimages/curl` is deployed here)
2. server-namespace (`nginx`, `nginx-2`is deployed here)

### Create the Namepsaces in all workload clusters (where istio is running)

- Gloo Mesh Management cluster would have the config namespace with the help of `configEnabled: true`.
- Workload clusters would have the actual applications deployed in the namespace.

```zsh
for CURRENT_CONTEXT in ${MGMT_CONTEXT} ${REMOTE_CONTEXT1} ${REMOTE_CONTEXT2}
do
  kubectl --context ${CURRENT_CONTEXT} create namespace client-namespace
  kubectl --context ${CURRENT_CONTEXT} create namespace server-namespace
done
```

### Add Istio Revision (`istio.io/rev`) label to Namespaces

```zsh
ISTIO_REVISION=1-15
for CURRENT_CONTEXT in ${REMOTE_CONTEXT1} ${REMOTE_CONTEXT2}
do
  kubectl --context ${CURRENT_CONTEXT} label namespace client-namespace istio.io/rev=${ISTIO_REVISION}
  kubectl --context ${CURRENT_CONTEXT} label namespace server-namespace istio.io/rev=${ISTIO_REVISION}
done
```

### Additional steps (just for OCP clusters)
```bash
echo ${REMOTE_CONTEXT1} ${REMOTE_CONTEXT2}
for CURRENT_CONTEXT in ${REMOTE_CONTEXT1} ${REMOTE_CONTEXT2}
do
echo; echo;
echo "CURRENT_CONTEXT is ${CURRENT_CONTEXT}"
oc --context "${CURRENT_CONTEXT}" adm policy add-scc-to-group anyuid system:serviceaccounts:client-namespace
oc --context "${CURRENT_CONTEXT}" adm policy add-scc-to-group anyuid system:serviceaccounts:server-namespace

cat <<EOF | oc --context "${CURRENT_CONTEXT}" -n client-namespace create -f -
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: istio-cni
EOF

cat <<EOF | oc --context "${CURRENT_CONTEXT}" -n server-namespace create -f -
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: istio-cni
EOF
done
```

### Run curl app http-client in `client-namespace` in workload cluster
```zsh
kubectl apply --context ${REMOTE_CONTEXT1} -f- <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: http-client
  namespace: client-namespace
  labels:
    account: http-client
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: http-client-deployment
  namespace: client-namespace
spec:
  selector:
    matchLabels:
      app: http-client
  replicas: 1
  template:
    metadata:
      labels:
        app: http-client
    spec:
      serviceAccount: http-client
      serviceAccountName: http-client
      containers:
      - name: http-client
        image: curlimages/curl:7.81.0
        command:
        - sleep
        - 20h
EOF

# verify rollout status-
kubectl --context ${REMOTE_CONTEXT1} -n client-namespace \
            rollout status deploy/http-client-deployment;
```

### Run nginx in `server-namespace` in workload cluster

```zsh
kubectl apply --context ${REMOTE_CONTEXT1} -f- <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nginx
  namespace: server-namespace
  labels:
    account: nginx
---
apiVersion: v1
kind: Service
metadata:
  name: nginx
  namespace: server-namespace
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
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: server-namespace
spec:
  selector:
    matchLabels:
      app: nginx
  replicas: 1
  template:
    metadata:
      labels:
        app: nginx
    spec:
      serviceAccount: nginx
      serviceAccountName: nginx
      containers:
      - name: nginx
        image: nginx:1.14.2
        ports:
        - containerPort: 80
EOF

# verify
kubectl --context ${REMOTE_CONTEXT1} -n server-namespace \
            rollout status deploy/nginx-deployment;
```

### Run `nginx-2` in `server-namespace` in workload cluster

```zsh
kubectl apply --context ${REMOTE_CONTEXT1} -f- <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nginx-2
  namespace: server-namespace
  labels:
    account: nginx-2
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-2
  namespace: server-namespace
  labels:
    app: nginx-2
spec:
  selector:
    app: nginx-2
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-2-deployment
  namespace: server-namespace
spec:
  selector:
    matchLabels:
      app: nginx-2
  replicas: 1
  template:
    metadata:
      labels:
        app: nginx-2
    spec:
      serviceAccount: nginx-2
      serviceAccountName: nginx-2
      containers:
      - name: nginx-2
        image: nginx:1.14.2
        ports:
        - containerPort: 80
EOF

# verify
kubectl --context ${REMOTE_CONTEXT1} -n server-namespace \
            rollout status deploy/nginx-2-deployment;

```

### Create the Workspaces (client-namespace, server-namespace) in management cluster

```zsh
for NAMESPACE in "client-namespace" "server-namespace"
do
kubectl apply --context ${MGMT_CONTEXT} -f- <<EOF
apiVersion: admin.gloo.solo.io/v2
kind: Workspace
metadata:
  name: ${NAMESPACE}
  namespace: gloo-mesh
spec:
  workloadClusters:
  - name: ${MGMT_CLUSTER}
    namespaces:
    - name: ${NAMESPACE}
    configEnabled: true
  - name: ${REMOTE_CLUSTER1}
    namespaces:
    - name: ${NAMESPACE}
    configEnabled: false
  - name: ${REMOTE_CLUSTER2}
    namespaces:
    - name: ${NAMESPACE}
    configEnabled: false
EOF
done
```

### Enable `serviceIsolation` and selectively import/export resources via `WorkspaceSettings`

```zsh
kubectl apply --context ${MGMT_CONTEXT} -f- <<EOF
apiVersion: admin.gloo.solo.io/v2
kind: WorkspaceSettings
metadata:
  name: server-namespace
  namespace: server-namespace
spec:
  exportTo:
# --- export only nginx service to client-namespace ---
  - workspaces:
    - name: client-namespace
    resources:
    - kind: SERVICE
      labels:
        app: nginx
  options:
# --- serviceIsolation and trimProxyConfig enabled ---
    serviceIsolation:
      enabled: true
      trimProxyConfig: true
EOF

kubectl apply --context ${MGMT_CONTEXT} -f- <<EOF
apiVersion: admin.gloo.solo.io/v2
kind: WorkspaceSettings
metadata:
  name: client-namespace
  namespace: client-namespace
spec:
  importFrom:
# --- client imports only nginx - selects by label ---
  - workspaces:
    - name: server-namespace
    resources:
    - kind: SERVICE
      labels:
        app: nginx
  options:
# --- serviceIsolation and trimProxyConfig enabled ---
    serviceIsolation:
      enabled: true
      trimProxyConfig: true
EOF
```

# Verification

- The `AuthorizationPolicy` for `nginx` and `nginx-2` are no more identical.
- `client-namespace` principals are no more a part of `nginx-2` AuthorizationPolicy since `nginx-2` is not exported.

### nginx-2 AuthorizationPolicy
```bash
kubectl --context $REMOTE_CONTEXT1 -n server-namespace get authorizationpolicy settings-nginx-2-80-server-namespace -o yaml
```

```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  creationTimestamp: "2023-01-19T23:52:18Z"
  generation: 1
  labels:
    agent.gloo.solo.io: gloo-mesh
    cluster.multicluster.solo.io: ""
    context.mesh.gloo.solo.io/cluster: drew-ocp-cluster2
    context.mesh.gloo.solo.io/namespace: server-namespace
    context.mesh.gloo.solo.io/workspace: server-namespace
    gloo.solo.io/parent_cluster: drew-ocp-cluster2
    gloo.solo.io/parent_group: ""
    gloo.solo.io/parent_kind: Service
    gloo.solo.io/parent_name: nginx-2
    gloo.solo.io/parent_namespace: server-namespace
    gloo.solo.io/parent_version: v1
    owner.gloo.solo.io/name: gloo-mesh
    reconciler.mesh.gloo.solo.io/name: translator
    relay.solo.io/cluster: drew-ocp-cluster2
  name: settings-nginx-2-80-server-namespace
  namespace: server-namespace
  resourceVersion: "2733312"
  uid: 6349b215-fa88-4515-af36-b1426ab12f29
spec:
  rules:
  - from:
    - source:
        principals:
        - drew-ocp-cluster2/ns/server-namespace/sa/builder
        - drew-ocp-cluster2/ns/server-namespace/sa/default
        - drew-ocp-cluster2/ns/server-namespace/sa/deployer
        - drew-ocp-cluster2/ns/server-namespace/sa/nginx
        - drew-ocp-cluster2/ns/server-namespace/sa/nginx-2
        - drew-ocp-cluster3/ns/server-namespace/sa/builder
        - drew-ocp-cluster3/ns/server-namespace/sa/default
        - drew-ocp-cluster3/ns/server-namespace/sa/deployer
    to:
    - operation:
        ports:
        - "80"
  selector:
    matchLabels:
      app: nginx-2
```

### nginx AuthorizationPolicy

```bash
kubectl --context $REMOTE_CONTEXT1 -n server-namespace get authorizationpolicy settings-nginx-80-server-namespace -o yaml
```

```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  creationTimestamp: "2023-01-19T23:52:18Z"
  generation: 2
  labels:
    agent.gloo.solo.io: gloo-mesh
    cluster.multicluster.solo.io: ""
    context.mesh.gloo.solo.io/cluster: drew-ocp-cluster2
    context.mesh.gloo.solo.io/namespace: server-namespace
    context.mesh.gloo.solo.io/workspace: server-namespace
    gloo.solo.io/parent_cluster: drew-ocp-cluster2
    gloo.solo.io/parent_group: ""
    gloo.solo.io/parent_kind: Service
    gloo.solo.io/parent_name: nginx
    gloo.solo.io/parent_namespace: server-namespace
    gloo.solo.io/parent_version: v1
    owner.gloo.solo.io/name: gloo-mesh
    reconciler.mesh.gloo.solo.io/name: translator
    relay.solo.io/cluster: drew-ocp-cluster2
  name: settings-nginx-80-server-namespace
  namespace: server-namespace
  resourceVersion: "2733326"
  uid: 6eb16c6e-dd84-48b0-90b4-9ec56c1cde23
spec:
  rules:
  - from:
    - source:
        principals:
        - drew-ocp-cluster2/ns/server-namespace/sa/builder
        - drew-ocp-cluster2/ns/server-namespace/sa/default
        - drew-ocp-cluster2/ns/server-namespace/sa/deployer
        - drew-ocp-cluster2/ns/server-namespace/sa/nginx
        - drew-ocp-cluster2/ns/server-namespace/sa/nginx-2
        - drew-ocp-cluster3/ns/server-namespace/sa/builder
        - drew-ocp-cluster3/ns/server-namespace/sa/default
        - drew-ocp-cluster3/ns/server-namespace/sa/deployer
    - source:
        principals:
        - drew-ocp-cluster2/ns/client-namespace/sa/builder
        - drew-ocp-cluster2/ns/client-namespace/sa/default
        - drew-ocp-cluster2/ns/client-namespace/sa/deployer
        - drew-ocp-cluster2/ns/client-namespace/sa/http-client
        - drew-ocp-cluster3/ns/client-namespace/sa/builder
        - drew-ocp-cluster3/ns/client-namespace/sa/default
        - drew-ocp-cluster3/ns/client-namespace/sa/deployer
    to:
    - operation:
        ports:
        - "80"
  selector:
    matchLabels:
      app: nginx
```

### Sidecar unimpacted

```bash
kubectl --context $REMOTE_CONTEXT1 -n client-namespace get sidecar sidecar-http-client-deployment--d382bbff3e8f88cef49fef20e6aaa7f -o yaml
```

```yaml
apiVersion: networking.istio.io/v1beta1
kind: Sidecar
metadata:
  creationTimestamp: "2023-01-19T23:52:19Z"
  generation: 1
  labels:
    agent.gloo.solo.io: gloo-mesh
    cluster.multicluster.solo.io: ""
    context.mesh.gloo.solo.io/cluster: drew-ocp-cluster2
    context.mesh.gloo.solo.io/namespace: client-namespace
    context.mesh.gloo.solo.io/workspace: client-namespace
    gloo.solo.io/parent_cluster: drew-ocp-cluster2
    gloo.solo.io/parent_group: apps
    gloo.solo.io/parent_kind: Deployment
    gloo.solo.io/parent_name: http-client-deployment
    gloo.solo.io/parent_namespace: client-namespace
    gloo.solo.io/parent_version: v1
    owner.gloo.solo.io/name: gloo-mesh
    reconciler.mesh.gloo.solo.io/name: translator
    relay.solo.io/cluster: drew-ocp-cluster2
  name: sidecar-http-client-deployment--d382bbff3e8f88cef49fef20e6aaa7f
  namespace: client-namespace
  resourceVersion: "2733327"
  uid: 04a4e3f9-2543-4b5c-9943-1eafd7cd7562
spec:
  egress:
  - hosts:
    - '*/nginx.server-namespace.svc.cluster.local'
  workloadSelector:
    labels:
      app: http-client
```

### nginx-2 is inaccessible
```bash
 kubectl --context $REMOTE_CONTEXT1 -n client-namespace exec -it deployments/http-client-deployment -- curl -I nginx-2.server-namespace.svc.cluster.local
```

```bash
HTTP/1.1 502 Bad Gateway
date: Thu, 19 Jan 2023 23:56:24 GMT
server: envoy
transfer-encoding: chunked
```

### nginx is accessible
```bash
kubectl --context $REMOTE_CONTEXT1 -n client-namespace exec -it deployments/http-client-deployment -- curl -I nginx.server-namespace.svc.cluster.local
```

```bash
HTTP/1.1 200 OK
server: envoy
date: Thu, 19 Jan 2023 23:56:31 GMT
content-type: text/html
content-length: 612
last-modified: Tue, 04 Dec 2018 14:44:49 GMT
etag: "5c0692e1-264"
accept-ranges: bytes
x-envoy-upstream-service-time: 2
```
