# Install Prometheus

- Install Prometheus via helm chart in `telemetry` namespace.
```bash
kubectl create namespace telemetry
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm -n telemetry install prometheus prometheus-community/prometheus
```

- View Prometheus Server on localhost.
```bash
kubectl port-forward service/prometheus-server 9090:80
```
_OR,_
- View Prometheus Server on Public IP by changing the type of the `Service` temporarily from `ClusterIP` to `LoadBalancer`
```bash
kubectl edit service prometheus-server
```
> Creates a public `LoadBalancer` and exposes an External IP.

## Navigation links

- [previous](https://github.com/find-arka/k8s-misc/blob/main/API-Gateway/README.md)
- [next](https://github.com/find-arka/k8s-misc/blob/main/API-Gateway/test-with-sample-application.md)
