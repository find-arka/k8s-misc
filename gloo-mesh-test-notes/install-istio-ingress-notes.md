## Download Istio locally

```bash
export ISTIO_VERSION=1.15.3
curl -L https://istio.io/downloadIstio | sh -
```

## Set environment variable

#### `HUB` for the Istio Version

[Docs link](https://support.solo.io/hc/en-us/articles/4414409064596)

```bash
export HUB="<Please update based on above Docs link>"
export INGRESS_GATEWAY_NAME="istio-ingressgateway-new"
```

## Override values using env variable
```bash
cat <<EOF > override.yaml
global:
  hub: ${HUB}
  tag: ${ISTIO_VERSION}-solo
gateways:
  istio-ingressgateway:
    name: ${INGRESS_GATEWAY_NAME}
    namespace: istio-gateways
    labels:
      istio: ingressgateway
    injectionTemplate: gateway
    ports:
    - name: http2
      port: 80
      targetPort: 8080
    - name: https
      port: 443
      targetPort: 8443
EOF
```

## helm dry run
```bash
helm --kube-context=${REMOTE_CONTEXT1} \
  -n istio-gateways \
  upgrade --install "${INGRESS_GATEWAY_NAME}" \
  ./istio-${ISTIO_VERSION}/manifests/charts/gateways/istio-ingress \
  -f override.yaml \
  --dry-run \
  --debug
```
