# Sample application setup

> Followed instrictions from [here](https://www.solo.io/blog/from-zero-to-gloo-edge-in-15-minutes-gke/) with some minor edits & some personal notes.

Create ServiceAccount, Deployment, Service for [httpbin](https://httpbin.org/).
- Image: `docker.io/kennethreitz/httpbin`
- [github repo](https://github.com/postmanlabs/httpbin)

```
kubectl apply -f https://raw.githubusercontent.com/solo-io/solo-blog/main/zero-to-gateway/httpbin-svc-dpl.yaml
```

## Routing

`matchers:` stanza: Match the path prefix `/api/httpbin` and replace it with `/`. So a path like `/api/httpbin/delay/1` will be sent to `httpbin` upstream with the path `/delay/1`.

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

- Get the IP and curl `/api/httpbin/delay/1` , `/api/httpbin/get` endpoints via the Gateway.

Get the IP-
```
kubectl -n gloo-system get svc gateway-proxy -o json | jq -r .status.loadBalancer.ingress[0].ip
```
_Or, make life easier with `glooctl`_
```bash
glooctl proxy url
```
*[How to install glooctl?](https://github.com/find-arka/k8s-misc/tree/v0.0.1/API-Gateway#glooctl)


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
