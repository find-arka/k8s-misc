# pod to pod test
for CURRENT_CONTEXT in ${MGMT_CONTEXT} ${REMOTE_CONTEXT1} ${REMOTE_CONTEXT2}
do
  kubectl --context ${CURRENT_CONTEXT} create namespace client-namespace
  kubectl --context ${CURRENT_CONTEXT} create namespace server-namespace
done

ISTIO_REVISION=1-16
for CURRENT_CONTEXT in ${REMOTE_CONTEXT1} ${REMOTE_CONTEXT2}
do
  kubectl --context ${CURRENT_CONTEXT} label namespace client-namespace istio.io/rev=${ISTIO_REVISION}
  kubectl --context ${CURRENT_CONTEXT} label namespace server-namespace istio.io/rev=${ISTIO_REVISION}
done

# OCP specific step
for CURRENT_CONTEXT in ${REMOTE_CONTEXT1} ${REMOTE_CONTEXT2}
do
  oc --context "${CURRENT_CONTEXT}" adm policy add-scc-to-group anyuid system:serviceaccounts:client-namespace
cat <<EOF | oc --context "${CURRENT_CONTEXT}" -n client-namespace create -f -
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: istio-cni
EOF

  oc --context "${CURRENT_CONTEXT}" adm policy add-scc-to-group anyuid system:serviceaccounts:server-namespace
cat <<EOF | oc --context "${CURRENT_CONTEXT}" -n server-namespace create -f -
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: istio-cni
EOF
done


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
done


kubectl apply --context ${MGMT_CONTEXT} -f- <<EOF
apiVersion: admin.gloo.solo.io/v2
kind: WorkspaceSettings
metadata:
  name: server-namespace
  namespace: server-namespace
spec:
  exportTo:
  - workspaces:
    - name: client-namespace
    resources:
    - kind: SERVICE
  options:
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
  - workspaces:
    - name: server-namespace
    resources:
    - kind: SERVICE
  options:
    serviceIsolation:
      enabled: true
      trimProxyConfig: true
EOF

for CURRENT_CONTEXT in ${REMOTE_CONTEXT1} ${REMOTE_CONTEXT2}
do
kubectl apply --context ${CURRENT_CONTEXT} --namespace client-namespace -f- <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: sleep
---
apiVersion: v1
kind: Service
metadata:
  name: sleep
  labels:
    app: sleep
    service: sleep
spec:
  ports:
  - port: 80
    name: http
  selector:
    app: sleep
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


# verify rollout status-
kubectl --context ${CURRENT_CONTEXT} -n client-namespace \
            rollout status deploy/sleep;

kubectl apply --context ${CURRENT_CONTEXT} -f- <<EOF
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
EOF

kubectl apply --context ${CURRENT_CONTEXT} -f- <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment-a
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
        instance: a
    spec:
      serviceAccount: nginx
      serviceAccountName: nginx
      containers:
      - name: nginx
        image: nginx:1.14.2
        ports:
        - containerPort: 80
EOF

kubectl apply --context ${CURRENT_CONTEXT} -f- <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment-b
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
        instance: b
    spec:
      serviceAccount: nginx
      serviceAccountName: nginx
      containers:
      - name: nginx
        image: nginx:1.14.2
        ports:
        - containerPort: 80
EOF
done

cat << EOF | kubectl --context ${MGMT_CONTEXT} apply -f -
apiVersion: networking.gloo.solo.io/v2
kind: RouteTable
metadata:
  name: sleep-to-nginx-route
  namespace: client-namespace
spec:
  hosts:
    - 'nginx.server-namespace.svc.cluster.local'
  workloadSelectors:
  - selector:
      namespace: client-namespace
      cluster: ${REMOTE_CONTEXT1}
  http:
    - name: nginx
      matchers:
      - uri:
          prefix: /
      forwardTo:
        destinations:
          - kind: SERVICE
            ref:
              name: nginx
              namespace: server-namespace
              cluster: "${REMOTE_CONTEXT1}"
            subset:
              instance: a
            port:
              number: 80
            weight: 100
          - kind: SERVICE
            ref:
              name: nginx
              namespace: server-namespace
              cluster: "${REMOTE_CONTEXT1}"
            subset:
              instance: b
            port:
              number: 80
            weight: 0
EOF

echo "sleeping for 15 seconds..."
sleep 15

for i in {1..20}
do
	kubectl --context=${REMOTE_CONTEXT1} -n client-namespace exec -ti deploy/sleep -c sleep -- curl -I nginx.server-namespace.svc.cluster.local >> "${HOME}/temp-output"
done

# # should be 20
SUCCESS_COUNT=$(cat ${HOME}/temp-output | grep 'HTTP/1.1 200 OK'| wc -l)

# # should be > 0
LOG_INSTANCE_A_COUNT=$(kubectl --context=${REMOTE_CONTEXT1} -n server-namespace logs -l instance=a | wc -l)

# # must be 0
LOG_INSTANCE_B_COUNT=$(kubectl --context=${REMOTE_CONTEXT1} -n server-namespace logs -l instance=b | wc -l)

rm ${HOME}/temp-output

echo "SUCCESS_COUNT=${SUCCESS_COUNT}"
echo "LOG_INSTANCE_A_COUNT=${LOG_INSTANCE_A_COUNT}"
echo "LOG_INSTANCE_B_COUNT=${LOG_INSTANCE_B_COUNT}"

if [ ${SUCCESS_COUNT} -eq 20 ] &&  [ ${LOG_INSTANCE_A_COUNT} -gt 0 ] && [ ${LOG_INSTANCE_B_COUNT} -eq 0 ]; then
      echo "test success";
else
    echo "test failure";
fi
