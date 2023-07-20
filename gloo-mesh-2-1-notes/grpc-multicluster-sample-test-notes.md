### Management Cluster - Gloo Mesh custom resources

```bash
kubectl --context ${MGMT_CONTEXT} apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: istio-grpc-example
  labels:
    name: istio-grpc-example
---
apiVersion: admin.gloo.solo.io/v2
kind: Workspace
metadata:
  name: istio-grpc-example
  namespace: gloo-mesh
  labels:
    allow_ingress: "true"
spec:
  workloadClusters:
  - name: '*'
    namespaces:
    - name: istio-grpc-example
---
apiVersion: admin.gloo.solo.io/v2
kind: WorkspaceSettings
metadata:
  name: istio-grpc-example
  namespace: istio-grpc-example
spec:
  exportTo:
  - workspaces:
    - name: platform
  importFrom:
  - workspaces:
    - name: platform
  options:
    eastWestGateways:
    - selector:
        labels:
          istio: eastwestgateway
    federation:
      enabled: false
      serviceSelector:
      - namespace: istio-grpc-example
    serviceIsolation:
      enabled: true
      trimProxyConfig: true
---
apiVersion: networking.gloo.solo.io/v2
kind: VirtualDestination
metadata:
  name: istio-grpc-example
  namespace: istio-grpc-example
spec:
  hosts:
  - istio-grpc-example.solo-io.mesh
  services:
  - labels:
      app: backend
  ports:
  - number: 50051
    protocol: TCP
    targetPort:
      name: grpc-backend
EOF
```

### Cluster1 - client application namespace, app deployment

```bash
kubectl --context ${REMOTE_CONTEXT1} apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: istio-grpc-example
  labels:
    name: istio-grpc-example
    istio-injection: enabled
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: client-0
  namespace: istio-grpc-example
  labels:
    app: client-0
spec:
  replicas: 1
  selector:
    matchLabels:
      app: client
      version: "0"
  template:
    metadata:
      labels:
        app: client
        version: "0"
    spec:
      containers:
        - name: python
          image: h3poteto/grpc_example-client-python:master
          imagePullPolicy: Always
          env:
            - name: SERVER_IP
# ----------- Using the DNS mentioned in the VirtualDestination -----------
              value: "istio-grpc-example.solo-io.mesh" 
            - name: SERVER_PORT
              value: "50051"
EOF
```

OpenShift Istio specific config steps
```bash
oc --context "${REMOTE_CONTEXT1}" adm policy add-scc-to-group anyuid "system:serviceaccounts:istio-grpc-example"

cat <<EOF | oc --context "${REMOTE_CONTEXT1}" -n istio-grpc-example create -f -
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: istio-cni
EOF
```

### Cluster2 - server application Namespace, Service, Deployment

```bash
kubectl --context ${REMOTE_CONTEXT2} apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: istio-grpc-example
  labels:
    name: istio-grpc-example
    istio-injection: enabled
---
apiVersion: v1
kind: Service
metadata:
  name: backend
  namespace: istio-grpc-example
  labels:
    app: backend
spec:
  ports:
  - port: 50051
    targetPort: 9090
    protocol: TCP
    # Port name is very important: https://istio.io/latest/docs/ops/configuration/traffic-management/protocol-selection/#explicit-protocol-selection
    # HTTP routes will be applied to platform service ports named ‘http-’/‘http2-’/‘grpc-*’
    name: grpc-backend
  selector:
    app: backend
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-0
  namespace: istio-grpc-example
  labels:
    app: backend-0
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
      version: "0"
  template:
    metadata:
      labels:
        app: backend
        version: "0"
    spec:
      containers:
        - name: python
          image: h3poteto/grpc_example-server-python:master
          imagePullPolicy: Always
          ports:
            - name: grpc
              containerPort: 9090
              protocol: TCP
          env:
            - name: SERVER_IP
              value: 0.0.0.0
            - name: SERVER_PORT
              value: "9090"
EOF
```

OpenShift config steps
```bash
oc --context "${REMOTE_CONTEXT2}" adm policy add-scc-to-group anyuid "system:serviceaccounts:istio-grpc-example"

cat <<EOF | oc --context "${REMOTE_CONTEXT2}" -n istio-grpc-example create -f -
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: istio-cni
EOF
```


### Verification from logs

```bash
kubectl --context "${REMOTE_CONTEXT1}" -n istio-grpc-example logs -f deploy/client-0
```

Output:
```bash
-------------------------------------------------------------
Name Kana Asumi, Age: 35
Name Ryoko Shintani, Age: 37
Name Ayane Sakura, Age: 25
Name Aoi Yuuki, Age: 26
.
.
.
```

### Verification via Access log

1. Client in Cluster 1

```bash
kubectl --context ${REMOTE_CONTEXT1} logs -f -n istio-grpc-example deployments/client-0 -c istio-proxy
```

2. E-W gateway in Cluster 2

```bash
k --context ${REMOTE_CONTEXT2} logs -f -n istio-gateways deployments/istio-eastwestgateway
```

3. Service in Cluster 2

```bash
kubectl --context ${REMOTE_CONTEXT2} logs -f -n istio-grpc-example deployments/backend-0 -c istio-proxy
```


### endpoints check

```bash
istioctl --context $REMOTE_CONTEXT1  pc endpoints --cluster "outbound|50051||istio-grpc-example.solo-io.mesh" -n istio-grpc-example deploy/client-0
```

```bash
ENDPOINT                STATUS      OUTLIER CHECK     CLUSTER
18.188.44.207:15443     HEALTHY     OK                outbound|50051||istio-grpc-example.solo-io.mesh
3.18.195.45:15443       HEALTHY     OK                outbound|50051||istio-grpc-example.solo-io.mesh
3.20.119.213:15443      HEALTHY     OK                outbound|50051||istio-grpc-example.solo-io.mesh
```
