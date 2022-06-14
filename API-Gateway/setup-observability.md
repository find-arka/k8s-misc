# Install Prometheus

> Documentation of Prometheus helm chart customization options is present [here](https://github.com/prometheus-community/helm-charts/blob/main/charts/prometheus/values.yaml)

- Install Prometheus via helm chart in `telemetry` namespace.
```bash
kubectl create namespace telemetry
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm -n telemetry install prometheus prometheus-community/prometheus
```

- Port Forward and view Prometheus Server on [localhost](http://localhost:9090).
```bash
kubectl -n telemetry port-forward service/prometheus-server 9090:80
```
_OR,_
- View Prometheus Server on Public IP by changing the type of the `Service` temporarily from `ClusterIP` to `LoadBalancer`
```bash
kubectl -n telemetry edit service prometheus-server
```
> Creates a public `LoadBalancer` and exposes an External IP.

## Navigation links

- Next: [API Gateway feature exploration](https://github.com/find-arka/k8s-misc/blob/main/API-Gateway/test-with-sample-application.md)
- Previous: [Setup AKS Cluster and install Gloo Edge](https://github.com/find-arka/k8s-misc/blob/main/API-Gateway/README.md)
