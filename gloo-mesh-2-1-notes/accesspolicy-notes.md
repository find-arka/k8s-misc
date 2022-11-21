# `AccessPolicy` test notes

## Global service isolation

- Added global WorkspaceSettings with serviceIsolation true
```bash
kubectl apply --context ${MGMT_CONTEXT} -n gloo-mesh -f- <<EOF
apiVersion: admin.gloo.solo.io/v2
kind: WorkspaceSettings
metadata:
 name: global
 namespace: gloo-mesh
spec:
 options:
   serviceIsolation:
     enabled: true
     trimProxyConfig: true
EOF
```

## environment overview

In our test setup, Workspaces & Namespaces have the same name (as requested).

We have 2 Namespace, Workspace objects:
- client-namespace (busybox-curl is deployed here)
- server-namespace (nginx is deployed here)

## Create the Namepsaces (client-namespace, server-namespace) in all clusters

```bash
for CURRENT_CONTEXT in ${MGMT_CONTEXT} ${REMOTE_CONTEXT1} ${REMOTE_CONTEXT2}
do
  kubectl --context ${CURRENT_CONTEXT} create namespace client-namespace
  kubectl --context ${CURRENT_CONTEXT} create namespace server-namespace
done
```
> Management cluster would have the config namespace. Workload clusters would have the applications deployed in the namespace.

## Add Istio revision label

```bash
ISTIO_REVISION=1-15
for CURRENT_CONTEXT in ${REMOTE_CONTEXT1} ${REMOTE_CONTEXT2}
do
  kubectl --context ${CURRENT_CONTEXT} label namespace client-namespace istio.io/rev=${ISTIO_REVISION}
  kubectl --context ${CURRENT_CONTEXT} label namespace server-namespace istio.io/rev=${ISTIO_REVISION}
done
```

## Create the Workspaces (client-namespace, server-namespace) in management cluster

```bash
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
  - name: ${MGMT_CONTEXT}
    namespaces:
    - name: ${NAMESPACE}
    configEnabled: true
  - name: '*' # --- Instead of name: '*' mentioning cluster names explicitly is recommended
    namespaces:
    - name: ${NAMESPACE}
    configEnabled: false
EOF
done
```

## Create the WorkspaceSettings (client-namespace, server-namespace) in management cluster

```bash
kubectl apply --context ${MGMT_CONTEXT} -f- <<EOF
apiVersion: admin.gloo.solo.io/v2
kind: WorkspaceSettings
metadata:
  name: server-namespace
  namespace: server-namespace
spec:
  options:
    serviceIsolation:
      enabled: false
      trimProxyConfig: false
EOF

kubectl apply --context ${MGMT_CONTEXT} -f- <<EOF
apiVersion: admin.gloo.solo.io/v2
kind: WorkspaceSettings
metadata:
  name: client-namespace
  namespace: client-namespace
spec:
  options:
# --- No one needs to discover and call a service running in this workspace ---
    serviceIsolation:
      enabled: true
      trimProxyConfig: true
EOF
```

## Run curl app http-client in `client-namespace` in workload cluster
```bash
kubectl apply --context ${REMOTE_CONTEXT1} -f- <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: http-client
  labels:
    app: http-client
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

# verify status
kubectl --context ${REMOTE_CONTEXT1} -n client-namespace \
            rollout status deploy/http-client-deployment;
```

## Run nginx in `server-namespace` in workload cluster

```bash
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

- Attempt curl-ing nginx from http-client
```bash
kubectl --context ${REMOTE_CONTEXT1} -n client-namespace \
  exec -it deployments/http-client-deployment \
  -- curl -I nginx.server-namespace.svc.cluster.local
```
Expectation: Access Denied (since there is no access policy)
Result: (Matches Expectation)
```bash
HTTP/1.1 403 Forbidden
content-length: 19
content-type: text/plain
date: Wed, 16 Nov 2022 17:15:36 GMT
server: envoy
x-envoy-upstream-service-time: 1
```

```
kubectl --context ${REMOTE_CONTEXT1} -n client-namespace \
  exec -it deployments/http-client-deployment \
  -- curl nginx.server-namespace.svc.cluster.local
```
`RBAC: access denied`
> **Matches Expectation**

- We would be adding the Access Policy for http-client to talk to nginx
Attempting with `applytoWorkloads` (since as per docs this is recommended)
```bash
kubectl apply --context ${MGMT_CONTEXT} -f- <<EOF
apiVersion: security.policy.gloo.solo.io/v2
kind: AccessPolicy
metadata:
  name: server-resource-access
  namespace: server-namespace
spec:
  applyToWorkloads:
  - selector:
      labels:
        app: nginx
      namespace: server-namespace
      cluster: ${REMOTE_CONTEXT1}
      workspace: server-namespace
  config:
    authn:
      tlsMode: STRICT
    authz:
      allowedClients:
      - serviceAccountSelector:
          cluster: ${REMOTE_CONTEXT1}
          namespace: client-namespace
          name: http-client
EOF
```

But this has error in gloo-mesh-ui
<img width="960" alt="Screenshot 2022-11-16 at 12 20 18 PM" src="https://user-images.githubusercontent.com/21124287/202249464-5037f844-38dd-4da9-8044-abfbc7aab0a7.png">

This is a UI bug (being addressed by eng) but not a blocker, since http-client can now talk to nginx
```
kubectl --context ${REMOTE_CONTEXT1} -n client-namespace \
  exec -it deployments/http-client-deployment \
  -- curl nginx.server-namespace.svc.cluster.local
```

```bash
HTTP/1.1 200 OK
server: envoy
date: Wed, 16 Nov 2022 17:21:49 GMT
content-type: text/html
content-length: 612
last-modified: Tue, 04 Dec 2018 14:44:49 GMT
etag: "5c0692e1-264"
accept-ranges: bytes
x-envoy-upstream-service-time: 7
```
> Note for future reference:
We just have the http-client to nginx allow access policy in place, and no other access policy is in place:
```bash
kubectl --context $MGMT_CONTEXT get accesspolicies -A
NAMESPACE          NAME                     AGE
server-namespace   server-resource-access   9m

kubectl --context $REMOTE_CONTEXT1 get accesspolicies -A
No resources found

kubectl --context $REMOTE_CONTEXT2 get accesspolicies -A
No resources found
```


## Test that no other apps (with diff serviceaccount) from cross namespace/workspace can talk to nginx
```bash
kubectl apply --context ${REMOTE_CONTEXT1} -f- <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: http-client-2
  namespace: client-namespace
  labels:
    account: http-client-2
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: http-client-2-deployment
  namespace: client-namespace
spec:
  selector:
    matchLabels:
      app: http-client-2
  replicas: 1
  template:
    metadata:
      labels:
        app: http-client-2
    spec:
      serviceAccount: http-client-2
      serviceAccountName: http-client-2
      containers:
      - name: http-client-2
        image: curlimages/curl:7.81.0
        command:
        - sleep
        - 20h
EOF
```

```bash
kubectl --context ${REMOTE_CONTEXT1} -n client-namespace \
  exec -it deployments/http-client-2-deployment \
  -- curl -I nginx.server-namespace.svc.cluster.local
```
Expectation: 403
Result:
```bash
HTTP/1.1 403 Forbidden
content-length: 19
content-type: text/plain
date: Wed, 16 Nov 2022 17:38:15 GMT
server: envoy
x-envoy-upstream-service-time: 21
```
Matches expectation

## Test that other apps (with diff serviceaccount) from SAME namespace/workspace can talk to nginx

```bash
kubectl apply --context ${REMOTE_CONTEXT1} -f- <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: http-client-server-namespace
  namespace: server-namespace
  labels:
    account: http-client-server-namespace
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: http-client-server-namespace-deployment
  namespace: server-namespace
spec:
  selector:
    matchLabels:
      app: http-client-server-namespace
  replicas: 1
  template:
    metadata:
      labels:
        app: http-client-server-namespace
    spec:
      serviceAccount: http-client-server-namespace
      serviceAccountName: http-client-server-namespace
      containers:
      - name: http-client-server-namespace
        image: curlimages/curl:7.81.0
        command:
        - sleep
        - 20h
EOF
```

```bash
kubectl --context ${REMOTE_CONTEXT1} -n server-namespace \
  exec -it deployments/http-client-server-namespace-deployment \
  -- curl -I nginx.server-namespace.svc.cluster.local
```
Expectation: 403 (since in the access policy we haven't allowed this comms to succeed based on service account selector)

```bash
HTTP/1.1 403 Forbidden
content-length: 19
content-type: text/plain
date: Wed, 16 Nov 2022 17:42:35 GMT
server: envoy
x-envoy-upstream-service-time: 26
```

## Test that after adding a second `serviceAccountSelector` another app is allowed to talk to nginx

- Before making the change in `AccessPolicy`, the exisiting Istio AuthorizationPolicy (generated via previous AccessPolicy) has only one principal:
`cluster-1-tech-sharing-demo/ns/client-namespace/sa/http-client`

```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  creationTimestamp: "2022-11-16T17:24:35Z"
  generation: 1
  labels:
    agent.gloo.solo.io: gloo-mesh
    cluster.multicluster.solo.io: ""
    context.mesh.gloo.solo.io/cluster: cluster-1-tech-sharing-demo
    context.mesh.gloo.solo.io/namespace: server-namespace
    context.mesh.gloo.solo.io/workspace: server-namespace
    gloo.solo.io/parent_cluster: cluster-1-tech-sharing-demo
    gloo.solo.io/parent_group: ""
    gloo.solo.io/parent_kind: Service
    gloo.solo.io/parent_name: nginx
    gloo.solo.io/parent_namespace: server-namespace
    gloo.solo.io/parent_version: v1
    owner.gloo.solo.io/name: gloo-mesh
    reconciler.mesh.gloo.solo.io/name: translator
    relay.solo.io/cluster: cluster-1-tech-sharing-demo
  name: accesspolicy-nginx-80-server-re-5d5a324fa06de66dbd19f7ce19dbab0
  namespace: server-namespace
  resourceVersion: "3706513"
  uid: 9d70ed8f-2152-4674-bb76-dc63e0112faa
spec:
  rules:
  - from:
    - source:
        principals:
        - cluster-1-tech-sharing-demo/ns/client-namespace/sa/http-client
    to:
    - operation:
        ports:
        - "80"
  selector:
    matchLabels:
      app: nginx
```

- Add 2nd serviceAccountSelector:
```bash
kubectl apply --context ${MGMT_CONTEXT} -f- <<EOF
apiVersion: security.policy.gloo.solo.io/v2
kind: AccessPolicy
metadata:
  name: server-resource-access
  namespace: server-namespace
spec:
  applyToWorkloads:
  - selector:
      labels:
        app: nginx
      namespace: server-namespace
      cluster: ${REMOTE_CONTEXT1}
      workspace: server-namespace
  config:
    authn:
      tlsMode: STRICT
    authz:
      allowedClients:
      - serviceAccountSelector:
          cluster: ${REMOTE_CONTEXT1}
          namespace: client-namespace
          name: http-client
# ----- Added selector for test -----
      - serviceAccountSelector:
          cluster: ${REMOTE_CONTEXT1}
          namespace: server-namespace
          name: http-client-server-namespace
EOF
```

- This created 2 Istio AccessPolicy objects-

```bash
kubectl --context ${REMOTE_CONTEXT1} get authorizationpolicy -n server-namespace \
  accesspolicy-server-resource-ac-e0076f3acb7ee1b362aadcbdf3feec8 -o yaml
```

```bash
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  creationTimestamp: "2022-11-16T17:49:39Z"
  generation: 1
  labels:
    agent.gloo.solo.io: gloo-mesh
    cluster.multicluster.solo.io: ""
    context.mesh.gloo.solo.io/cluster: cluster-1-tech-sharing-demo
    context.mesh.gloo.solo.io/namespace: server-namespace
    context.mesh.gloo.solo.io/workspace: server-namespace
    gloo.solo.io/parent_cluster: cluster-1-tech-sharing-demo
    gloo.solo.io/parent_group: ""
    gloo.solo.io/parent_kind: Namespace
    gloo.solo.io/parent_name: server-namespace
    gloo.solo.io/parent_namespace: ""
    gloo.solo.io/parent_version: v1
    owner.gloo.solo.io/name: gloo-mesh
    reconciler.mesh.gloo.solo.io/name: translator
    relay.solo.io/cluster: cluster-1-tech-sharing-demo
  name: accesspolicy-server-resource-ac-e0076f3acb7ee1b362aadcbdf3feec8
  namespace: server-namespace
  resourceVersion: "3714758"
  uid: 2a2bb72b-25b5-49a7-a4e1-15c8cfab98ae
spec:
  rules:
  - from:
    - source:
        principals:
        - cluster-1-tech-sharing-demo/ns/client-namespace/sa/http-client
    - source:
        principals:
        - cluster-1-tech-sharing-demo/ns/server-namespace/sa/http-client-server-namespace
  selector:
    matchLabels:
      app: nginx
```

```bash
kubectl --context ${REMOTE_CONTEXT1} get authorizationpolicy -n server-namespace settings-nginx-80-server-namespace -o yaml
```

```bash
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  creationTimestamp: "2022-11-16T17:49:39Z"
  generation: 1
  labels:
    agent.gloo.solo.io: gloo-mesh
    cluster.multicluster.solo.io: ""
    context.mesh.gloo.solo.io/cluster: cluster-1-tech-sharing-demo
    context.mesh.gloo.solo.io/namespace: server-namespace
    context.mesh.gloo.solo.io/workspace: server-namespace
    gloo.solo.io/parent_cluster: cluster-1-tech-sharing-demo
    gloo.solo.io/parent_group: ""
    gloo.solo.io/parent_kind: Service
    gloo.solo.io/parent_name: nginx
    gloo.solo.io/parent_namespace: server-namespace
    gloo.solo.io/parent_version: v1
    owner.gloo.solo.io/name: gloo-mesh
    reconciler.mesh.gloo.solo.io/name: translator
    relay.solo.io/cluster: cluster-1-tech-sharing-demo
  name: settings-nginx-80-server-namespace
  namespace: server-namespace
  resourceVersion: "3714759"
  uid: 573c64a5-c007-4a40-8add-614f4b6954b5
spec:
  rules:
  - from:
    - source:
        principals:
        - cluster-1-tech-sharing-demo/ns/server-namespace/sa/default
        - cluster-1-tech-sharing-demo/ns/server-namespace/sa/http-client-server-namespace
        - cluster-1-tech-sharing-demo/ns/server-namespace/sa/nginx
        - cluster-2-tech-sharing-demo/ns/server-namespace/sa/default
    to:
    - operation:
        ports:
        - "80"
  selector:
    matchLabels:
      app: nginx
```

- test access

```bash
kubectl --context ${REMOTE_CONTEXT1} -n server-namespace \
  exec -it deployments/http-client-server-namespace-deployment \
  -- curl -I nginx.server-namespace.svc.cluster.local
```
Expectation: 200 OK
Result:
```bash
HTTP/1.1 200 OK
server: envoy
date: Wed, 16 Nov 2022 17:54:19 GMT
content-type: text/html
content-length: 612
last-modified: Tue, 04 Dec 2018 14:44:49 GMT
etag: "5c0692e1-264"
accept-ranges: bytes
x-envoy-upstream-service-time: 28
```

Matches expectation.

# import-export service by labels example
```bash
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
    serviceIsolation:
      enabled: true
      trimProxyConfig: true
EOF

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
    serviceIsolation:
      enabled: true
      trimProxyConfig: true
EOF
```

check endpoints
```bash
istioctl --context $REMOTE_CONTEXT1 -n client-namespace pc endpoints deploy/http-client-deployment
```

output
```bash
ENDPOINT                                                STATUS      OUTLIER CHECK     CLUSTER
10.0.0.30:80                                            HEALTHY     OK                outbound|80||http-client.client-namespace.svc.cluster.local
10.0.1.51:80                                            HEALTHY     OK                outbound|80||nginx.server-namespace.svc.cluster.local
127.0.0.1:15000                                         HEALTHY     OK                prometheus_stats
127.0.0.1:15020                                         HEALTHY     OK                agent
172.20.62.76:9977                                       HEALTHY     OK                envoy_accesslog_service
172.20.62.76:9977                                       HEALTHY     OK                envoy_metrics_service
unix://./etc/istio/proxy/XDS                            HEALTHY     OK                xds-grpc
unix://./var/run/secrets/workload-spiffe-uds/socket     HEALTHY     OK                sds-grpc
```

```
kubectl --context ${REMOTE_CONTEXT1} -n client-namespace \
  exec -it deployments/http-client-deployment \
  -- curl -I nginx.server-namespace.svc.cluster.local
```
```
HTTP/1.1 200 OK
server: envoy
date: Mon, 21 Nov 2022 17:16:01 GMT
content-type: text/html
content-length: 612
last-modified: Tue, 04 Dec 2018 14:44:49 GMT
etag: "5c0692e1-264"
accept-ranges: bytes
x-envoy-upstream-service-time: 7
```
