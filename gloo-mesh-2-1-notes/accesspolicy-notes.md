# Notes from _"zero-trust"_ testing

Contains the test notes related to _zero-trust_ with Gloo Mesh 2.x

We have tested the following 2 approaches for setting up trust boundaries:

1. Selectively importing exporting objects via `WorkspaceSettings`, and enabling Workspace level `serviceIsolation`.
2. Deny all traffic by default and use `AccessPolicy` to explicitly allow traffic selectively.

# Test environment overview

> In our test environment, Workspaces & Namespaces have the same name.

We have 2 Namespace and 2 corresponding Workspace objects:
1. client-namespace (`curlimages/curl` is deployed here)
2. server-namespace (`nginx` is deployed here)

## Create the Namepsaces in all workload clusters (where istio is running)

- Gloo Mesh Management cluster would have the config namespace with the help of `configEnabled: true`.
- Workload clusters would have the actual applications deployed in the namespace.

```zsh
for CURRENT_CONTEXT in ${MGMT_CONTEXT} ${REMOTE_CONTEXT1} ${REMOTE_CONTEXT2}
do
  kubectl --context ${CURRENT_CONTEXT} create namespace client-namespace
  kubectl --context ${CURRENT_CONTEXT} create namespace server-namespace
done
```

## Add Istio Revision (`istio.io/rev`) label to Namespaces

```zsh
ISTIO_REVISION=1-15
for CURRENT_CONTEXT in ${REMOTE_CONTEXT1} ${REMOTE_CONTEXT2}
do
  kubectl --context ${CURRENT_CONTEXT} label namespace client-namespace istio.io/rev=${ISTIO_REVISION}
  kubectl --context ${CURRENT_CONTEXT} label namespace server-namespace istio.io/rev=${ISTIO_REVISION}
done
```

## Run curl app http-client in `client-namespace` in workload cluster
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

## Run nginx in `server-namespace` in workload cluster

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

## Create the Workspaces (client-namespace, server-namespace) in management cluster

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

## Appproach 1: Enable `serviceIsolation` and selectively import/export resources via `WorkspaceSettings`

- In this approach, access to a service would be allowed within a Workspace. If there are multiple namespaces within this workspace, access would be allowed by default across those namespaces which is within the `Workspace`.
- Access to a service would be also allowed from another `Workspace` to which the service was exported to. The other Workspace also needs to write the complimentary `importFrom` spec in `WorkspaceSettings` for this cross Workspace access to work.

### Create the `WorkspaceSettings`

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

### Test Access from `client-namespace` Workspace - expect to get 200

```zsh
kubectl --context ${REMOTE_CONTEXT1} -n client-namespace \
  exec -it deployments/http-client-deployment \
  -- curl -I nginx.server-namespace.svc.cluster.local
```

Output:
```zsh
HTTP/1.1 200 OK
server: envoy
date: Wed, 23 Nov 2022 18:53:31 GMT
content-type: text/html
content-length: 612
last-modified: Tue, 04 Dec 2018 14:44:49 GMT
etag: "5c0692e1-264"
accept-ranges: bytes
x-envoy-upstream-service-time: 7
```
This matches our expectation.

### Check endpoints

```zsh
istioctl --context $REMOTE_CONTEXT1 -n client-namespace pc endpoints deploy/http-client-deployment
```

```zsh
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

### Test Access from `server-namespace` Workspace - expect to get 200

- Deploy the same `http-client` application in `server-namespace` and attempt accessing.
- We expect a 200 since the traffic is within the Workspace boundary.
```zsh
kubectl --context ${REMOTE_CONTEXT1} -n server-namespace \
  exec -it deployments/http-client-deployment \
  -- curl -I nginx.server-namespace.svc.cluster.local
```
Output:
```zsh
HTTP/1.1 200 OK
server: envoy
date: Wed, 23 Nov 2022 21:25:26 GMT
content-type: text/html
content-length: 612
last-modified: Tue, 04 Dec 2018 14:44:49 GMT
etag: "5c0692e1-264"
accept-ranges: bytes
x-envoy-upstream-service-time: 12
```
This matches our expectation.


### Test Access from a 3rd Workspace - expect to get 502

- Deploy the same `http-client` application in a 3rd namespace and attempt accessing. 
- Deployed the app in an existing namespace: `bookinfo-backends`
- We expect a 502 since the traffic is outside the Workspace boundary and also the service is not exported, imported.
```zsh
kubectl --context ${REMOTE_CONTEXT1} -n bookinfo-backends \
  exec -it deployments/http-client-deployment \
  -- curl -I nginx.server-namespace.svc.cluster.local
```
Output:
```zsh
HTTP/1.1 502 Bad Gateway
date: Wed, 23 Nov 2022 21:57:03 GMT
server: envoy
transfer-encoding: chunked
```

```bash
istioctl --context $REMOTE_CONTEXT1 -n bookinfo-backends pc endpoints deploy/http-client-deployment | grep nginx
```
Zero rows returned. No endpoint for `nginx` known


## Approach 2: Test notes from `AccessPolicy` approach

### Create the `WorkspaceSettings`

```zsh
kubectl apply --context ${MGMT_CONTEXT} -f- <<EOF
apiVersion: admin.gloo.solo.io/v2
kind: WorkspaceSettings
metadata:
  name: server-namespace
  namespace: server-namespace
spec:
  options:
  # -- serviceIsolation disabled since we plan to use Access Policies to setup zero trust --
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
  # -- serviceIsolation disabled since we plan to use Access Policies to setup zero trust --
    serviceIsolation:
      enabled: false
      trimProxyConfig: false
EOF
```

### setup deny all for these workspaces
```zsh
kubectl apply --context ${MGMT_CONTEXT} -f- <<EOF
apiVersion: security.policy.gloo.solo.io/v2
kind: AccessPolicy
metadata:
  name: allow-nothing
  namespace: client-namespace
spec:
  applyToWorkloads:
  - {}
  config:
    authn:
      tlsMode: STRICT
    authz: {}
EOF

kubectl apply --context ${MGMT_CONTEXT} -f- <<EOF
apiVersion: security.policy.gloo.solo.io/v2
kind: AccessPolicy
metadata:
  name: allow-nothing
  namespace: server-namespace
spec:
  applyToWorkloads:
  - {}
  config:
    authn:
      tlsMode: STRICT
    authz: {}
EOF
```
> These above access polcies currently create Istio `AuthorizationPolicy` with `spec: {}` in respective namespaces.

### Test Access - expect to get 403

Attempt curl-ing `nginx` from `http-client`. Should give a 403 since we have the `allow-nothing` AccessPolicy in both the namespaces
```zsh
kubectl --context ${REMOTE_CONTEXT1} -n client-namespace \
  exec -it deployments/http-client-deployment \
  -- curl -I nginx.server-namespace.svc.cluster.local
```

Output:
```zsh
HTTP/1.1 403 Forbidden
content-length: 19
content-type: text/plain
date: Tue, 22 Nov 2022 17:40:21 GMT
server: envoy
x-envoy-upstream-service-time: 7
```
This matches our expectation.

### Add allow `AccessPolicy`

- We would be adding the Access Policy for only `http-client` to talk to `nginx`
- We would be using `serviceAccountSelector` for this setup.
- We would be using `applyToWorkloads` in `AccessPolicy.spec`. As per [docs here](https://docs.solo.io/gloo-mesh-enterprise/latest/reference/api/github.com.solo-io.gloo-mesh-enterprise.api.gloo.solo.io.policy.v2.security.access_policy/#security.policy.gloo.solo.io.AccessPolicySpec) this is recommended over `applyToDestinations`
- Select `allowedClients` by `serviceAccountSelector`. `ServiceAccount` name, `Cluster` name, `Namespace` name is used to make the selection.

```zsh
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

- This creates an Istio `AuthorizationPolicy` with desired spec-
```zsh
...
spec:
  rules:
  - from:
    - source:
        principals:
        - cluster-1-tech-sharing-demo/ns/client-namespace/sa/http-client
  selector:
    matchLabels:
      app: nginx
```

### Test Access - expect to get 200

```zsh
kubectl --context ${REMOTE_CONTEXT1} -n client-namespace \
  exec -it deployments/http-client-deployment \
  -- curl -I nginx.server-namespace.svc.cluster.local
```

Output:
```zsh
HTTP/1.1 200 OK
server: envoy
date: Tue, 22 Nov 2022 17:51:00 GMT
content-type: text/html
content-length: 612
last-modified: Tue, 04 Dec 2018 14:44:49 GMT
etag: "5c0692e1-264"
accept-ranges: bytes
x-envoy-upstream-service-time: 7
```
This matches our expectation.

### Test that no other apps (with `different serviceaccount`) from `cross workspace` can not talk to nginx
```zsh
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
# verify rollout status-
kubectl --context ${REMOTE_CONTEXT1} -n client-namespace \
            rollout status deploy/http-client-2-deployment;
```

### Test Access - expect to get 403

```zsh
kubectl --context ${REMOTE_CONTEXT1} -n client-namespace \
  exec -it deployments/http-client-2-deployment \
  -- curl -I nginx.server-namespace.svc.cluster.local
```

Output:
```zsh
HTTP/1.1 403 Forbidden
content-length: 19
content-type: text/plain
date: Tue, 22 Nov 2022 17:56:43 GMT
server: envoy
x-envoy-upstream-service-time: 4
```
This matches our expectation.

### Test that other apps (with `differet serviceaccount`) from `same workspace` can not talk to nginx

```zsh
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

# verify rollout status-
kubectl --context ${REMOTE_CONTEXT1} -n server-namespace \
            rollout status deploy/http-client-server-namespace-deployment;
```

### Test Access - expect to get 403
```zsh
kubectl --context ${REMOTE_CONTEXT1} -n server-namespace \
  exec -it deployments/http-client-server-namespace-deployment \
  -- curl -I nginx.server-namespace.svc.cluster.local
```

```zsh
HTTP/1.1 403 Forbidden
content-length: 19
content-type: text/plain
date: Tue, 22 Nov 2022 18:01:19 GMT
server: envoy
x-envoy-upstream-service-time: 4
```
This matches our expectation.

### Test that after adding a second `serviceAccountSelector` another app is allowed to talk to nginx

> Before making the change in `AccessPolicy`, the exisiting Istio AuthorizationPolicy (generated via existing `AccessPolicy` object) has only one principal:
`cluster-1-tech-sharing-demo/ns/client-namespace/sa/http-client`

```yaml
spec:
  rules:
  - from:
    - source:
        principals:
        - cluster-1-tech-sharing-demo/ns/client-namespace/sa/http-client
  selector:
    matchLabels:
      app: nginx
```

- Adding 2nd `serviceAccountSelector` to the `AccessPolicy`. Select by `ServiceAccount` name, `Cluster` name, `Namespace` name.
```zsh
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
# -------- Added serviceAccountSelector for this test --------
      - serviceAccountSelector:
          cluster: ${REMOTE_CONTEXT1}
          namespace: server-namespace
          name: http-client-server-namespace
# ------------------------------------------------------------
EOF
```

> As a result, new `rules` get added to the Istio `AuthorizationPolicy`:

```yaml
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

### Test Access - expect to get 200

```zsh
kubectl --context ${REMOTE_CONTEXT1} -n server-namespace \
  exec -it deployments/http-client-server-namespace-deployment \
  -- curl -I nginx.server-namespace.svc.cluster.local
```

Output:
```zsh
HTTP/1.1 200 OK
server: envoy
date: Tue, 22 Nov 2022 18:09:59 GMT
content-type: text/html
content-length: 612
last-modified: Tue, 04 Dec 2018 14:44:49 GMT
etag: "5c0692e1-264"
accept-ranges: bytes
x-envoy-upstream-service-time: 4
```
This matches our expectation.

### Problem with this approach

- `istioctl pc endpoints` output shows all the endpoints. Ideally, we would like this to be trimmed down.
```zsh
istioctl --context $REMOTE_CONTEXT1 -n client-namespace pc endpoints deploy/http-client-deployment
```
```zsh
ENDPOINT                                                STATUS      OUTLIER CHECK     CLUSTER
10.0.0.123:9091                                         HEALTHY     OK                outbound|9091||gloo-mesh-agent.gloo-mesh.svc.cluster.local
10.0.0.123:9977                                         HEALTHY     OK                outbound|9977||gloo-mesh-agent.gloo-mesh.svc.cluster.local
10.0.0.123:9988                                         HEALTHY     OK                outbound|9988||gloo-mesh-agent.gloo-mesh.svc.cluster.local
10.0.0.168:9080                                         HEALTHY     OK                outbound|9080||details.bookinfo-backends.svc.cluster.local
10.0.0.209:8080                                         HEALTHY     OK                outbound|80||istio-ingressgateway.istio-gateways.svc.cluster.local
10.0.0.209:8443                                         HEALTHY     OK                outbound|443||istio-ingressgateway.istio-gateways.svc.cluster.local
10.0.0.211:9402                                         HEALTHY     OK                outbound|9402||cert-manager.cert-manager.svc.cluster.local
10.0.0.232:10250                                        HEALTHY     OK                outbound|443||cert-manager-webhook.cert-manager.svc.cluster.local
10.0.0.252:9080                                         HEALTHY     OK                outbound|9080||reviews.bookinfo-backends.svc.cluster.local
10.0.0.30:80                                            HEALTHY     OK                outbound|80||http-client.client-namespace.svc.cluster.local
10.0.0.37:15012                                         HEALTHY     OK                outbound|15012||istio-eastwestgateway.istio-gateways.svc.cluster.local
10.0.0.37:15017                                         HEALTHY     OK                outbound|15017||istio-eastwestgateway.istio-gateways.svc.cluster.local
10.0.0.37:15021                                         HEALTHY     OK                outbound|15021||istio-eastwestgateway.istio-gateways.svc.cluster.local
10.0.0.37:15443                                         HEALTHY     OK                outbound|15443||istio-eastwestgateway.istio-gateways.svc.cluster.local
10.0.0.38:15010                                         HEALTHY     OK                outbound|15010||istiod-1-15.istio-system.svc.cluster.local
10.0.0.38:15012                                         HEALTHY     OK                outbound|15012||istiod-1-15.istio-system.svc.cluster.local
10.0.0.38:15014                                         HEALTHY     OK                outbound|15014||istiod-1-15.istio-system.svc.cluster.local
10.0.0.38:15017                                         HEALTHY     OK                outbound|443||istiod-1-15.istio-system.svc.cluster.local
10.0.0.41:9080                                          HEALTHY     OK                outbound|9080||ratings.bookinfo-backends.svc.cluster.local
10.0.0.69:80                                            HEALTHY     OK                outbound|80||http-client-new-namespace.new-client-namespace.svc.cluster.local
10.0.1.129:9080                                         HEALTHY     OK                outbound|9080||reviews.bookinfo-backends.svc.cluster.local
10.0.1.160:53                                           HEALTHY     OK                outbound|53||kube-dns.kube-system.svc.cluster.local
10.0.1.188:80                                           HEALTHY     OK                outbound|80||nginx-2.server-namespace.svc.cluster.local
10.0.1.51:80                                            HEALTHY     OK                outbound|80||nginx.server-namespace.svc.cluster.local
10.0.1.55:53                                            HEALTHY     OK                outbound|53||kube-dns.kube-system.svc.cluster.local
10.0.1.56:9080                                          HEALTHY     OK                outbound|9080||productpage.bookinfo-frontends.svc.cluster.local
10.0.1.81:8080                                          HEALTHY     OK                outbound|8080||aws-pca-issuer-aws-privateca-issuer.cert-manager.svc.cluster.local
10.0.2.71:443                                           HEALTHY     OK                outbound|443||kubernetes.default.svc.cluster.local
10.0.3.145:443                                          HEALTHY     OK                outbound|443||kubernetes.default.svc.cluster.local
127.0.0.1:15000                                         HEALTHY     OK                prometheus_stats
127.0.0.1:15020                                         HEALTHY     OK                agent
172.20.62.76:9977                                       HEALTHY     OK                envoy_accesslog_service
172.20.62.76:9977                                       HEALTHY     OK                envoy_metrics_service
unix://./etc/istio/proxy/XDS                            HEALTHY     OK                xds-grpc
unix://./var/run/secrets/workload-spiffe-uds/socket     HEALTHY     OK                sds-grpc
```
- To use `AccessPolicy` and define which services are allowed to interact with which services we have to first disable `serviceIsolation` in the WorkspaceSettings object-

```yaml
    serviceIsolation:
      enabled: false
```

- `trimProxyConfig` is currently tied to `serviceIsolation` and if `serviceIsolation` is disabled, trimProxyConfig is disabled as well. Thus, we are seeing all the entries in the `istioctl pc endpoints`.

> There is a github issue currently open on this subject so that `trimProxyConfig` could be separated from `serviceIsolation` logic.
