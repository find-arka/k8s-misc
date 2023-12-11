#!/bin/bash
set -e
# Docs: https://docs.solo.io/gloo-mesh-enterprise/main/observability/tools/prometheus/setup/
export UPGRADE_VERSION=2.2.0
helm repo update
helm search repo gloo-mesh-enterprise --versions --devel | grep "${UPGRADE_VERSION}"

# Save the kubeconfig contexts for your clusters.
# Run kubectl config get-contexts, look for your cluster in the CLUSTER column,
# and get the context name in the NAME column. Note: Do not use context names with underscores. 
# The context name is used as a SAN specification in the generated certificate that connects workload clusters to the management cluster, and underscores in SAN are not FQDN compliant. 
# You can rename a context by running kubectl config rename-context "<oldcontext>" <newcontext>.
export MGMT_CONTEXT="mgmt-cluster-arka"
export REMOTE_CONTEXT1="cluster-1-arka"
export REMOTE_CONTEXT2="cluster-2-arka"

echo; echo;
echo "#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%"
echo "Getting helm release names from the gloo-mesh namespace"
echo "#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%"
GM_MGMT_SERVER_HELM_RELEASE_NAME=$(helm -n gloo-mesh --kube-context $MGMT_CONTEXT ls | grep "gloo-mesh-enterprise" | cut -f1)
GM_AGENT_HELM_RELEASE_NAME_CLUSTER1=$(helm -n gloo-mesh --kube-context $REMOTE_CONTEXT1 ls | grep "gloo-mesh-agent" | cut -f1)
GM_AGENT_HELM_RELEASE_NAME_CLUSTER2=$(helm -n gloo-mesh --kube-context $REMOTE_CONTEXT2 ls | grep "gloo-mesh-agent" | cut -f1)

echo "[DEBUG] Helm release name of mgmt server: ${GM_MGMT_SERVER_HELM_RELEASE_NAME}"
echo "[DEBUG] Helm release name of agent cluster1: ${GM_AGENT_HELM_RELEASE_NAME_CLUSTER1}"
echo "[DEBUG] Helm release name of agent cluster2: ${GM_AGENT_HELM_RELEASE_NAME_CLUSTER2}"

echo; echo;
echo "#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%"
echo "Upgrade management server"
echo "#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%"
echo; echo "[INFO] Get existing helm override values for mgmt server"
helm -n gloo-mesh get values "${GM_MGMT_SERVER_HELM_RELEASE_NAME}" \
    --kube-context ${MGMT_CONTEXT} > values-mgmt-plane-env-backup.yaml;
ls -lh values-mgmt-plane-env-backup.yaml;
echo;

# "--set legacyMetricsPipeline.enabled=false" Helm option is used to
# fully migrate to the Gloo OTel metrics pipeline, and disable the default metrics pipeline.
helm upgrade --install "${GM_MGMT_SERVER_HELM_RELEASE_NAME}" gloo-mesh-enterprise/gloo-mesh-enterprise \
    --namespace gloo-mesh \
    --kube-context ${MGMT_CONTEXT} \
    --set legacyMetricsPipeline.enabled=false \
    --set metricsgateway.enabled=true \
    --set metricsgateway.resources.requests.cpu=300m \
    --set metricsgateway.resources.requests.memory=1Gi \
    --set metricsgateway.resources.limits.cpu=600m \
    --set metricsgateway.resources.limits.memory="2Gi" \
    --version ${UPGRADE_VERSION} \
    --values values-mgmt-plane-env-backup.yaml \
    --wait;

echo;
kubectl --context ${MGMT_CONTEXT} -n gloo-mesh rollout status deploy/gloo-mesh-mgmt-server;
sleep 5;

echo; echo;
echo "#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%"
echo "Upgrade agents"
echo "#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%"
METRICS_GATEWAY_IP=$(kubectl get svc -n gloo-mesh gloo-metrics-gateway --context $MGMT_CONTEXT -o jsonpath='{.status.loadBalancer.ingress[0].*}')
METRICS_GATEWAY_PORT=$(kubectl -n gloo-mesh get service gloo-metrics-gateway --context $MGMT_CONTEXT -o jsonpath='{.spec.ports[?(@.name=="otlp")].port}')
METRICS_GATEWAY_ADDRESS=${METRICS_GATEWAY_IP}:${METRICS_GATEWAY_PORT}
echo; echo "[INFO] METRICS_GATEWAY_ADDRESS=${METRICS_GATEWAY_ADDRESS}"

echo; echo "[INFO] Get existing helm override values for the agent in cluster 1 to reuse in the helm upgrade"
helm -n gloo-mesh get values "${GM_AGENT_HELM_RELEASE_NAME_CLUSTER1}" \
    --kube-context $REMOTE_CONTEXT1 > "values-data-plane-env-${REMOTE_CONTEXT1}-backup.yaml";
ls -lh "values-data-plane-env-${REMOTE_CONTEXT1}-backup.yaml"
echo

helm upgrade --install "${GM_AGENT_HELM_RELEASE_NAME_CLUSTER1}" gloo-mesh-agent/gloo-mesh-agent \
    --namespace gloo-mesh \
    --kube-context=${REMOTE_CONTEXT1} \
    --set metricscollector.enabled=true \
    --set metricscollector.config.exporters.otlp.endpoint="${METRICS_GATEWAY_ADDRESS}" \
    --set legacyMetricsPipeline.enabled=false \
    --set metricscollector.resources.requests.cpu=500m \
    --set metricscollector.resources.requests.memory="1Gi" \
    --set metricscollector.resources.limits.cpu=2 \
    --set metricscollector.resources.limits.memory="2Gi" \
    --set metricscollector.ports.otlp.hostPort=0 \
    --set metricscollector.ports.otlp-http.hostPort=0 \
    --set metricscollector.ports.jaeger-compact.hostPort=0 \
    --set metricscollector.ports.jaeger-thrift.hostPort=0 \
    --set metricscollector.ports.jaeger-grpc.hostPort=0 \
    --set metricscollector.ports.zipkin.hostPort=0 \
    --version ${UPGRADE_VERSION} \
    --values "values-data-plane-env-${REMOTE_CONTEXT1}-backup.yaml" \
    --wait;

echo; echo "[INFO] Checking status of the gloo-metrics-collector-agent Daemonset"
kubectl --context ${REMOTE_CONTEXT1} -n gloo-mesh get daemonset gloo-metrics-collector-agent;

echo; echo "[INFO] Cluster 2: Get existing helm override values for the agent to reuse in the helm upgrade"
helm -n gloo-mesh get values "${GM_AGENT_HELM_RELEASE_NAME_CLUSTER2}" \
    --kube-context ${REMOTE_CONTEXT2} > "values-data-plane-env-${REMOTE_CONTEXT2}-backup.yaml";
ls -lh "values-data-plane-env-${REMOTE_CONTEXT2}-backup.yaml"
echo

helm upgrade --install "${GM_AGENT_HELM_RELEASE_NAME_CLUSTER2}" gloo-mesh-agent/gloo-mesh-agent \
    --namespace gloo-mesh \
    --kube-context=${REMOTE_CONTEXT2} \
    --set metricscollector.enabled=true \
    --set metricscollector.config.exporters.otlp.endpoint="${METRICS_GATEWAY_ADDRESS}" \
    --set legacyMetricsPipeline.enabled=false \
    --set metricscollector.resources.requests.cpu=500m \
    --set metricscollector.resources.requests.memory="1Gi" \
    --set metricscollector.resources.limits.cpu=2 \
    --set metricscollector.resources.limits.memory="2Gi" \
    --set metricscollector.ports.otlp.hostPort=0 \
    --set metricscollector.ports.otlp-http.hostPort=0 \
    --set metricscollector.ports.jaeger-compact.hostPort=0 \
    --set metricscollector.ports.jaeger-thrift.hostPort=0 \
    --set metricscollector.ports.jaeger-grpc.hostPort=0 \
    --set metricscollector.ports.zipkin.hostPort=0 \
    --version ${UPGRADE_VERSION} \
    --values "values-data-plane-env-${REMOTE_CONTEXT2}-backup.yaml" \
    --wait;

echo; echo "[INFO] Checking status of the gloo-metrics-collector-agent Daemonset"
kubectl --context ${REMOTE_CONTEXT2} -n gloo-mesh get daemonset gloo-metrics-collector-agent;

echo; echo;
echo "#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%"
echo "Verification of metrics being exposed via gloo-metrics-gateway"
echo "#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%"
kubectl --context ${MGMT_CONTEXT} -n gloo-mesh \
    port-forward deploy/gloo-metrics-gateway 9091 & PID=$!
sleep 3
ALL_METRICS=$(curl -s http://localhost:9091/metrics)
for METRIC in "istio_requests_total" "istio_request_duration_milliseconds" "istio_request_duration_milliseconds_bucket" "istio_request_duration_milliseconds_count" "istio_request_duration_milliseconds_sum" "istio_tcp_sent_bytes_total" "istio_tcp_received_bytes_total"
do
    OUTPUT=$(echo "${ALL_METRICS}" | grep -c "${METRIC}") 
    echo; echo "[INFO] Occurence of ${METRIC}: ${OUTPUT}"
done
kill $PID


## Test notes from setting up metrics pipeline when we have custom certificate

- Create a Certficate object for the metrics gateway in the management cluster

kind: Certificate
apiVersion: cert-manager.io/v1
metadata:
  name: gloo-metrics-gateway
  namespace: gloo-mesh
spec:
  secretName: gloo-metrics-gateway-tls-secret
  duration: 2h
  issuerRef:
# ---------------- Issuer for Gloo Mesh certs ---------------------------
    group: awspca.cert-manager.io
    kind: AWSPCAClusterIssuer
    name: aws-pca-cluster-issuer-gloo-mesh-$MGMT_CONTEXT
# ---------------- Issuer for Gloo Mesh certs ---------------------------
  commonName: gloo-metrics-gateway
  dnsNames:
    - gloo-metrics-gateway.gloo-mesh
    - gloo-metrics-gateway.gloo-mesh.svc
  usages:
    - server auth
    - client auth
    - digital signature
    - key encipherment
  privateKey:
    algorithm: "RSA"
    size: 2048


- This would create the prerequisite gloo-metrics-gateway-tls-secret

- Run the helm upgrade with the following override:

--set metricsgatewayCustomization.disableCertGeneration=true

## Workload cluster steps:

- following is a workaround. we have a github issue to perform this more gracefully:

# get the root CA cert
RELAY_ROOT_TLS_SECRET_CA_CERT=$(kubectl --context ${REMOTE_CONTEXT1} -n gloo-mesh get secret relay-client-tls-secret -o yaml | yq '.data."ca.crt"' | base64 -d)

# cluster 1
kubectl --context ${REMOTE_CONTEXT1} -n gloo-mesh create secret generic relay-root-tls-secret --from-literal="ca.crt"=${RELAY_ROOT_TLS_SECRET_CA_CERT}

# cluster 2
kubectl --context ${REMOTE_CONTEXT2} -n gloo-mesh create secret generic relay-root-tls-secret --from-literal="ca.crt"=${RELAY_ROOT_TLS_SECRET_CA_CERT}


