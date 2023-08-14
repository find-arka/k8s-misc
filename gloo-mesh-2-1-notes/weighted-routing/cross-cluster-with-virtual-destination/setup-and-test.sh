# pod to pod test
for CURRENT_CONTEXT in ${MGMT_CONTEXT} ${REMOTE_CONTEXT1} ${REMOTE_CONTEXT2}
do
  kubectl --context ${CURRENT_CONTEXT} create namespace weighted-routing-multicluster-space
done

for CURRENT_CONTEXT in ${REMOTE_CONTEXT1} ${REMOTE_CONTEXT2}
do
  kubectl --context ${CURRENT_CONTEXT} label namespace weighted-routing-multicluster-space istio-injection=enabled
done

# OCP specific step
for CURRENT_CONTEXT in ${REMOTE_CONTEXT1} ${REMOTE_CONTEXT2}
do
  oc --context "${CURRENT_CONTEXT}" adm policy add-scc-to-group anyuid system:serviceaccounts:weighted-routing-multicluster-space
cat <<EOF | oc --context "${CURRENT_CONTEXT}" -n weighted-routing-multicluster-space create -f -
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: istio-cni
EOF
done

export NAMESPACE="weighted-routing-multicluster-space"

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
  - name: ${REMOTE_CONTEXT1}
    namespaces:
    - name: ${NAMESPACE}
    configEnabled: false
  - name: ${REMOTE_CONTEXT2}
    namespaces:
    - name: ${NAMESPACE}
    configEnabled: false
EOF

kubectl apply --context ${MGMT_CONTEXT} -f- <<EOF
apiVersion: admin.gloo.solo.io/v2
kind: WorkspaceSettings
metadata:
  name: weighted-routing-multicluster-space
  namespace: weighted-routing-multicluster-space
spec:
  options:
  options:
    federation:
      enabled: false
    eastWestGateways:
    - selector:
        labels:
          istio: eastwestgateway
    serviceIsolation:
      enabled: true
      trimProxyConfig: true
EOF

kubectl apply --context ${REMOTE_CONTEXT1} --namespace weighted-routing-multicluster-space -f- <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: sleep
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sleep
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sleep
  template:
    metadata:
      labels:
        app: sleep
    spec:
      serviceAccountName: sleep
      containers:
      - name: sleep
        image: governmentpaas/curl-ssl:terraform-14
        command: ["/bin/sleep", "3650d"]
        imagePullPolicy: IfNotPresent
        volumeMounts:
        - mountPath: /etc/sleep/tls
          name: secret-volume
      volumes:
      - name: secret-volume
        secret:
          secretName: sleep-secret
          optional: true
EOF

for CURRENT_CONTEXT in ${REMOTE_CONTEXT1} ${REMOTE_CONTEXT2}
do
kubectl apply --context ${CURRENT_CONTEXT} -f- <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nginx
  namespace: $NAMESPACE
  labels:
    account: nginx
---
apiVersion: v1
kind: Service
metadata:
  name: nginx
  namespace: $NAMESPACE
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
EOF

kubectl apply --context ${CURRENT_CONTEXT} -f- <<EOF
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: index-html-configmap-a
  namespace: $NAMESPACE
data:
  index.html: |
    <html>
    <h1>Welcome to nginx!</h1>
    </br>
    <h1> Cluster: ${CURRENT_CONTEXT} </h1>
    <h1> instance: a </h1>
    </html>
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment-a
  namespace: $NAMESPACE
spec:
  selector:
    matchLabels:
      app: nginx
      instance: a
  replicas: 1
  template:
    metadata:
      labels:
        app: nginx
        instance: a
    spec:
      serviceAccount: nginx
      serviceAccountName: nginx
      containers:
      - name: nginx
        image: nginx:1.14.2
        ports:
        - containerPort: 80
        volumeMounts:
        - name: nginx-index-file
          mountPath: /usr/share/nginx/html/
      volumes:
      - name: nginx-index-file
        configMap:
          name: index-html-configmap-a
EOF

kubectl apply --context ${CURRENT_CONTEXT} -f- <<EOF
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: index-html-configmap-b
  namespace: $NAMESPACE
data:
  index.html: |
    <html>
    <h1>Welcome to nginx!</h1>
    </br>
    <h1> Cluster: ${CURRENT_CONTEXT} </h1>
    <h1> instance: b </h1>
    </html>
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment-b
  namespace: $NAMESPACE
spec:
  selector:
    matchLabels:
      app: nginx
      instance: b
  replicas: 1
  template:
    metadata:
      labels:
        app: nginx
        instance: b
    spec:
      serviceAccount: nginx
      serviceAccountName: nginx
      containers:
      - name: nginx
        image: nginx:1.14.2
        ports:
        - containerPort: 80
        volumeMounts:
        - name: nginx-index-file
          mountPath: /usr/share/nginx/html/
      volumes:
      - name: nginx-index-file
        configMap:
          name: index-html-configmap-b
EOF

# verify rollout status-
kubectl --context ${CURRENT_CONTEXT} -n weighted-routing-multicluster-space \
            rollout status deploy/nginx-deployment-a;
kubectl --context ${CURRENT_CONTEXT} -n weighted-routing-multicluster-space \
            rollout status deploy/nginx-deployment-b;
done


kubectl --context ${MGMT_CONTEXT} apply -f - <<EOF
apiVersion: networking.gloo.solo.io/v2
kind: VirtualDestination
metadata:
  name: vd-nginx-multicluster-a-b-global
  namespace: weighted-routing-multicluster-space
  labels:
# ---- FailoverPolicy uses this label for selcting the resource ---
    failover-test: "true"
spec:
  hosts:
  - nginx-multicluster-a-b.global
  services:
  - namespace: weighted-routing-multicluster-space
    labels:
      app: nginx
  ports:
    - number: 80
      protocol: HTTP
---
apiVersion: resilience.policy.gloo.solo.io/v2
kind: FailoverPolicy
metadata:
  name: failover-nginx-a-b-new
  namespace: weighted-routing-multicluster-space
spec:
  applyToDestinations:
  - kind: VIRTUAL_DESTINATION
    selector:
      labels:
# ---- VIRTUAL_DESTINATION which has this label is selected ---
        failover-test: "true"
  config:
    localityMappings:
# ---- If services in all zones in us-west-2 are failing, failover to us-west-1 ---
    - from:
        region: us-west-2
      to:
      - region: us-west-1
# ---- If services in all zones in us-west-1 are failing, failover to us-west-2 ---
    - from:
        region: us-west-1
      to:
      - region: us-west-2
---
apiVersion: networking.gloo.solo.io/v2
kind: RouteTable
metadata:
  name: sleep-to-nginx-route
  namespace: weighted-routing-multicluster-space
spec:
  hosts:
    - 'nginx-multicluster-a-b.global'
  workloadSelectors:
  - selector:
      namespace: weighted-routing-multicluster-space
      cluster: ${REMOTE_CONTEXT1}
  http:
    - name: nginx
      matchers:
      - uri:
          prefix: /
      forwardTo:
        destinations:
          - kind: VIRTUAL_DESTINATION
            ref:
              name: vd-nginx-multicluster-a-b-global
              namespace: weighted-routing-multicluster-space
              cluster: "${MGMT_CONTEXT}"
            subset:
              instance: a
            port:
              number: 80
            weight: 100
          - kind: VIRTUAL_DESTINATION
            ref:
              name: vd-nginx-multicluster-a-b-global
              namespace: weighted-routing-multicluster-space
              cluster: "${MGMT_CONTEXT}"
            subset:
              instance: b
            port:
              number: 80
            weight: 0
EOF

echo "sleeping for 5 seconds..."
sleep 5

echo; echo "Check endpoints and priority"
NAMESPACE=weighted-routing-multicluster-space
DEPLOYMENT_NAME=sleep
VIRTUAL_DESTINATION_NAME=nginx-multicluster-a-b.global

istioctl pc endpoints  --context $REMOTE_CONTEXT1 -n "${NAMESPACE}" "deploy/${DEPLOYMENT_NAME}" | grep "${VIRTUAL_DESTINATION_NAME}" | grep instance

kubectl --context $REMOTE_CONTEXT1 -n $NAMESPACE port-forward deployments/$DEPLOYMENT_NAME 15000:15000 &
PID=$!
sleep 10
echo
curl -s localhost:15000/clusters | grep $VIRTUAL_DESTINATION_NAME | grep instance- | grep ":priority"
echo
kill $PID


# test hitting the endpoint
rm -rf "${HOME}/all-nginx-hits.txt"
for i in {1..20}
do
  echo; echo "Attempt #${i}";echo;
  OUTPUT=$(kubectl --context=${REMOTE_CONTEXT1} -n $NAMESPACE exec -ti deploy/sleep -c sleep -- curl -s "http://nginx-multicluster-a-b.global/")
  echo $OUTPUT
  echo $OUTPUT | grep -A1 "Cluster" >> "${HOME}/all-nginx-hits.txt"
done

INSTANCE_A_COUNT=$(cat "${HOME}/all-nginx-hits.txt" | grep 'instance: a' | wc -l)
INSTANCE_B_COUNT=$(cat "${HOME}/all-nginx-hits.txt" | grep 'instance: b' | wc -l)

CLUSTER1_COUNT=$(cat "${HOME}/all-nginx-hits.txt" | grep ${REMOTE_CONTEXT1} | wc -l)
CLUSTER2_COUNT=$(cat "${HOME}/all-nginx-hits.txt" | grep ${REMOTE_CONTEXT2} | wc -l)

echo; echo "--Output--"
echo; echo "nginx instance a hits: $INSTANCE_A_COUNT"
echo; echo "nginx instance b hits: $INSTANCE_B_COUNT"
echo; echo "Cluster 1 hits: $CLUSTER1_COUNT"
echo; echo "Cluster 2 hits: $CLUSTER2_COUNT"
rm -rf "${HOME}/all-nginx-hits.txt"

echo; echo "INSTANCE_A_COUNT should be 20 and INSTANCE_B_COUNT should be 0."
echo "Only Cluster 1 should have hits"


## scenario 2
echo; echo "--Scale down deployment in cluster 1--"; echo;
kubectl --context ${REMOTE_CONTEXT1} -n $NAMESPACE scale deployment nginx-deployment-a --replicas=0
kubectl --context ${REMOTE_CONTEXT1} -n $NAMESPACE scale deployment nginx-deployment-b --replicas=0

kubectl --context ${REMOTE_CONTEXT1} -n $NAMESPACE \
            rollout status deploy/nginx-deployment-a;
kubectl --context ${REMOTE_CONTEXT1} -n $NAMESPACE \
            rollout status deploy/nginx-deployment-b;

echo "sleeping for 5 seconds..."
sleep 5

# test hitting the endpoint
rm -rf "${HOME}/all-nginx-hits.txt"
for i in {1..20}
do
  echo; echo "Attempt #${i}";echo;
  OUTPUT=$(kubectl --context=${REMOTE_CONTEXT1} -n "${NAMESPACE}" exec -ti deploy/sleep -c sleep -- curl -s "http://nginx-multicluster-a-b.global/")
  echo $OUTPUT
  echo $OUTPUT | grep -A1 "Cluster" >> "${HOME}/all-nginx-hits.txt"
done

INSTANCE_A_COUNT=$(cat "${HOME}/all-nginx-hits.txt" | grep 'instance: a' | wc -l)
INSTANCE_B_COUNT=$(cat "${HOME}/all-nginx-hits.txt" | grep 'instance: b' | wc -l)

CLUSTER1_COUNT=$(cat "${HOME}/all-nginx-hits.txt" | grep ${REMOTE_CONTEXT1} | wc -l)
CLUSTER2_COUNT=$(cat "${HOME}/all-nginx-hits.txt" | grep ${REMOTE_CONTEXT2} | wc -l)

echo; echo "--Output--"
echo; echo "nginx instance a hits: $INSTANCE_A_COUNT"
echo; echo "nginx instance b hits: $INSTANCE_B_COUNT"
echo; echo "Cluster 1 hits: $CLUSTER1_COUNT"
echo; echo "Cluster 2 hits: $CLUSTER2_COUNT"
rm -rf "${HOME}/all-nginx-hits.txt"

echo; echo "INSTANCE_A_COUNT should be 20 and INSTANCE_B_COUNT should be 0."
echo "Only Cluster 2 should have hits"


## scenario 3
echo; echo "--Scale up deployment in cluster 1--"; echo;
kubectl --context ${REMOTE_CONTEXT1} -n $NAMESPACE scale deployment nginx-deployment-a --replicas=1
kubectl --context ${REMOTE_CONTEXT1} -n $NAMESPACE scale deployment nginx-deployment-b --replicas=1

kubectl --context ${REMOTE_CONTEXT1} -n $NAMESPACE \
            rollout status deploy/nginx-deployment-a;
kubectl --context ${REMOTE_CONTEXT1} -n $NAMESPACE \
            rollout status deploy/nginx-deployment-b;

echo "sleeping for 5 seconds..."
sleep 5

# test hitting the endpoint
rm -rf "${HOME}/all-nginx-hits.txt"
for i in {1..20}
do
  echo; echo "Attempt #${i}";echo;
  OUTPUT=$(kubectl --context=${REMOTE_CONTEXT1} -n "${NAMESPACE}" exec -ti deploy/sleep -c sleep -- curl -s "http://nginx-multicluster-a-b.global/")
  echo $OUTPUT
  echo $OUTPUT | grep -A1 "Cluster" >> "${HOME}/all-nginx-hits.txt"
done

INSTANCE_A_COUNT=$(cat "${HOME}/all-nginx-hits.txt" | grep 'instance: a' | wc -l)
INSTANCE_B_COUNT=$(cat "${HOME}/all-nginx-hits.txt" | grep 'instance: b' | wc -l)

CLUSTER1_COUNT=$(cat "${HOME}/all-nginx-hits.txt" | grep ${REMOTE_CONTEXT1} | wc -l)
CLUSTER2_COUNT=$(cat "${HOME}/all-nginx-hits.txt" | grep ${REMOTE_CONTEXT2} | wc -l)

echo; echo "--Output--"
echo; echo "nginx instance a hits: $INSTANCE_A_COUNT"
echo; echo "nginx instance b hits: $INSTANCE_B_COUNT"
echo; echo "Cluster 1 hits: $CLUSTER1_COUNT"
echo; echo "Cluster 2 hits: $CLUSTER2_COUNT"
rm -rf "${HOME}/all-nginx-hits.txt"

echo; echo "INSTANCE_A_COUNT should be 20 and INSTANCE_B_COUNT should be 0."
echo "Only Cluster 1 should have hits"

unset NAMESPACE