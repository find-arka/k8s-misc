> Notes from my test environment based on [TCP Proxy](https://docs.solo.io/gloo-edge/master/guides/traffic_management/listener_configuration/tcp_proxy/)

## Traffic Management with gloo - TCP Proxy test

- Create a pod and expose with a service-
```bash
kubectl apply -n gloo-system -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  labels:
    gloo: tcp-echo
  name: tcp-echo
spec:
  containers:
  - image: soloio/tcp-echo:latest
    imagePullPolicy: IfNotPresent
    name: tcp-echo
  restartPolicy: Always
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: gloo
  name: tcp-echo
spec:
  ports:
  - name: http
    port: 1025
    protocol: TCP
    targetPort: 1025
  selector:
    gloo: tcp-echo
EOF
```
> Note: gloo automatically created the `Upstream` resource along with the service. The `Upstream` name is in the format: `<namespace>-<service>-<port>`

- Create a `Gateway` resource referring this upstream-  
```bash
kubectl apply -n gloo-system -f - <<EOF
apiVersion: gateway.solo.io/v1
kind: Gateway
metadata:
  name: tcp
  namespace: gloo-system
spec:
  bindAddress: '::'
  bindPort: 8000
  tcpGateway:
    tcpHosts:
    - name: one
      destination:
        single:
          upstream:
            name: gloo-system-tcp-echo-1025
            namespace: gloo-system
  useProxyProto: false
EOF
```
> Note: Gateway created a `Proxy` resource in the background with name `gateway-proxy`

- Edit the service `gateway-proxy` and add the following yaml (route?)
```bash
kubectl edit svc `gateway-proxy` -n gloo-system
```
```yaml
  - name: tcp
    nodePort: 30197
    port: 8000
    protocol: TCP
    targetPort: 8000
```
