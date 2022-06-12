# API Gateway feature exploration

Run a sample application on the already running K8s cluster, and test various features of the Gloo Edge API Gateway
> Based on the [solo.io blog](https://www.solo.io/blog/from-zero-to-gloo-edge-in-15-minutes-gke/)  

## Run Sample application

Create ServiceAccount, Deployment, Service for [httpbin](https://httpbin.org/).
- Image: `docker.io/kennethreitz/httpbin`
- [github repo](https://github.com/postmanlabs/httpbin)

```bash
kubectl apply -f https://raw.githubusercontent.com/solo-io/solo-blog/main/zero-to-gateway/httpbin-svc-dpl.yaml
```

An `Upstream` object also gets created implicitly in the namespace where Gloo is deployed.
- Get upstream info using `glooctl` CLI
```bash
glooctl get upstream default-httpbin-8000
```

```bash
# Expected output
+----------------------+------------+----------+------------------------+
|       UPSTREAM       |    TYPE    |  STATUS  |        DETAILS         |
+----------------------+------------+----------+------------------------+
| default-httpbin-8000 | Kubernetes | Accepted | svc name:      httpbin |
|                      |            |          | svc namespace: default |
|                      |            |          | port:          8000    |
|                      |            |          |                        |
+----------------------+------------+----------+------------------------+
```

## Function Discovery

- Edit the `Upstream` object created-
```bash
kubectl -n gloo-system edit upstream default-httpbin-8000
```

- Add the following config which links with OpenAPI spec file for `httpbin` service.
```yaml
    serviceSpec:
      rest:
        swaggerInfo:
          url: https://raw.githubusercontent.com/solo-io/solo-blog/main/zero-to-gateway/httpbin-openapi.json
```

- Enable function discovery by adding a label `function_discovery=enabled`
```bash
kubectl label namespace default discovery.solo.io/function_discovery=enabled
```

- Get list of functions discovered-
```bash
glooctl get upstream default-httpbin-8000
```

```bash
# Expected output
+----------------------+------------+----------+------------------------+
|       UPSTREAM       |    TYPE    |  STATUS  |        DETAILS         |
+----------------------+------------+----------+------------------------+
| default-httpbin-8000 | Kubernetes | Accepted | svc name:      httpbin |
|                      |            |          | svc namespace: default |
|                      |            |          | port:          8000    |
|                      |            |          | REST service:          |
|                      |            |          | functions:             |
|                      |            |          | - /anything            |
|                      |            |          | - /base64              |
|                      |            |          | - /brotli              |
|                      |            |          | - /bytes               |
|                      |            |          | - /cache               |
|                      |            |          | - /deflate             |
|                      |            |          | - /delay               |
|                      |            |          | - /delete              |
|                      |            |          | - /get                 |
|                      |            |          | - /gzip                |
|                      |            |          | - /headers             |
|                      |            |          | - /ip                  |
|                      |            |          | - /patch               |
|                      |            |          | - /post                |
|                      |            |          | - /put                 |
|                      |            |          | - /redirect-to         |
|                      |            |          | - /response-headers    |
|                      |            |          | - /status              |
|                      |            |          | - /stream              |
|                      |            |          | - /user-agent          |
|                      |            |          | - /uuid                |
|                      |            |          | - /xml                 |
|                      |            |          |                        |
+----------------------+------------+----------+------------------------+
```

## Configure Routing

Match the path prefix `/api/httpbin` and replace it with `/`

`/api/httpbin/delay/1` => `httpbin` upstream with the path `/delay/1`
`/api/httpbin/get`     => `httpbin` upstream with the path `/get`

```bash
kubectl -n gloo-system apply -f - <<EOF
apiVersion: gateway.solo.io/v1
kind: VirtualService
metadata:
  name: default
  namespace: gloo-system
spec:
  virtualHost:
    domains:
    - '*'
    routes:
    - matchers:
      - prefix: /api/httpbin
      options:
        regexRewrite: 
          pattern:
            regex: '/api/httpbin/'
          substitution: '/'
      routeAction:
        single:
          upstream:
            name: default-httpbin-8000
            namespace: gloo-system
EOF
```

### Validate Routing

- Get the IP of `gateway-proxy` Service and curl `/api/httpbin/delay/1` , `/api/httpbin/get` endpoints.

Get the IP using standard `kubectl` command-
```
kubectl -n gloo-system get svc gateway-proxy -o json | jq -r .status.loadBalancer.ingress[0].ip
```

_OR, make life easier with `glooctl`_

```bash
glooctl proxy url
```
> _[How to install `glooctl`?]_(https://github.com/find-arka/k8s-misc/tree/v0.0.1/API-Gateway#glooctl)


- Test hitting the endpoints

`/delay/n` endpoint:
```bash
curl $(glooctl proxy url)/api/httpbin/delay/1 -i
```

`/get` endpoint
```bash
curl $(glooctl proxy url)/api/httpbin/get -i
```

## Configure Timeout

Edit `VirtualService` spec, and add 5 seconds timeout (`timeout: '5s'`) under `options` in `routes`
```bash
kubectl -n gloo-system apply -f - <<EOF
apiVersion: gateway.solo.io/v1
kind: VirtualService
metadata:
  name: default
  namespace: gloo-system
spec:
  virtualHost:
    domains:
    - '*'
    routes:
    - matchers:
      - prefix: /api/httpbin
      options:
        timeout: '5s'
        regexRewrite: 
          pattern:
            regex: '/api/httpbin/'
          substitution: '/'
      routeAction:
        single:
          upstream:
            name: default-httpbin-8000
            namespace: gloo-system
EOF
```

### Validate Timeout Configuration

Delay time > configured timeout time, results in `504 Gateway Timeout`

- Test with delay 7 seconds
```bash
# 504 response expected
curl $(glooctl proxy url)/api/httpbin/delay/7 -i
```

- Test with delay 4 seconds
```bash
# 200 response expected
curl $(glooctl proxy url)/api/httpbin/delay/4 -i
```

## Metrics

- envoy by default exposes metrics on `/stats` endpoint.
- gateway-proxy runs envoy wrapper named `gloo-envoy-wrapper`, and exposes envoy metrics on port `8081`.

### Validate - view metrics in Prometheus

> Pre-req: [Run Prometheus in the K8s cluster](https://github.com/find-arka/k8s-misc/blob/main/API-Gateway/setup-observability.md)

- View on localhost after port-forwarding.
```bash
kubectl port-forward service/prometheus-server 9090:80
```
Go to http://localhost:9090

_OR,_

- If `prometheus-server` Service is running as `LoadBalancer`, go to the External IP of the `LoadBalancer`
```bash
kubectl -n telemetry get svc prometheus-server -o json | jq -r .status.loadBalancer.ingress[0].ip
```

#### Check Success response count(200) and Gateway Timeout(504) response count 

```
envoy_cluster_upstream_rq{envoy_response_code="200",envoy_cluster_name=~".*httpbin.*"}
```

```
envoy_cluster_upstream_rq{envoy_response_code="504",envoy_cluster_name=~".*httpbin.*"}
```

Forcefully timeout a couple of times-
```bash
# 504 response expected
curl $(glooctl proxy url)/api/httpbin/delay/7 -i
```
within a minute, the 504 count should increase.

## Navigation links
- Previous: [Install Prometheus](https://github.com/find-arka/k8s-misc/blob/main/API-Gateway/setup-observability.md)

### Cleanup

Delete the cluster.
```bash
az aks delete \
    --resource-group $RG \
    --name $MY_CLUSTER_NAME
```
