# Setup observability

- Install Prometheus via helm chart.
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install prometheus prometheus-community/prometheus
```

- View Prometheus Server on localhost.
```bash
kubectl port-forward service/prometheus-server 9090:80
```

- View Prometheus Server on Public IP by changing the type of the Service temporarily from `ClusterIP` to `LoadBalancer`
```bash
kubectl edit service prometheus-server
```
> Creates a public `LoadBalancer` and exposes an External IP. Integration with External DNS, enabling TLS is important for production usage.

## Navigation links
- [previous](https://github.com/find-arka/k8s-misc/blob/v0.0.2/API-Gateway/test-with-sample-application.md)
