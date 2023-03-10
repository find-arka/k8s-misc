################################################################################
# Platform specific components
################################################################################
# Create Namespaces
kubectl create ns httpbin-1
kubectl create ns httpbin-2

##
# Add Istio injection related label
# Either by,
# kubectl label ns httpbin-1 istio-injection=enabled
# kubectl label ns httpbin-2 istio-injection=enabled
# Or by, 
# using the `istio.io/rev` label
##
export ISTIO_REVISION=1-16
kubectl label namespace httpbin-1 istio.io/rev=${ISTIO_REVISION} --overwrite
kubectl label namespace httpbin-2 istio.io/rev=${ISTIO_REVISION} --overwrite

# OCP specific configuration
oc adm policy add-scc-to-group anyuid system:serviceaccounts:httpbin-1
oc adm policy add-scc-to-group anyuid system:serviceaccounts:httpbin-2

# Create istio-cni NetworkAttachmentDefinition for these namespaces
cat <<EOF | kubectl -n httpbin-1 create -f -
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: istio-cni
EOF

cat <<EOF | kubectl -n httpbin-2 create -f -
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: istio-cni
EOF

################################################################################
# Application specific components
################################################################################

# Deploy the ServiceEntry objects, ServiceAccount, Service, Deployment
kubectl -n httpbin-1 apply -f https://raw.githubusercontent.com/istio/istio/1.16.1/samples/extauthz/local-ext-authz.yaml
kubectl -n httpbin-2 apply -f https://raw.githubusercontent.com/istio/istio/1.16.1/samples/extauthz/local-ext-authz.yaml

# Apply the EnvoyFilter
kubectl -n httpbin-1 apply -f filter.yaml
kubectl -n httpbin-2 apply -f filter.yaml

# Apply Gateway and the VirtualService
kubectl -n httpbin-1 apply -f gw-vs-httpbin-1.yaml
kubectl -n httpbin-2 apply -f gw-vs-httpbin-2.yaml

################################################################################
# Verification
################################################################################
export INGRESS_ENDPOINT=[REDACTED]
# These respond with 200 OK, since they have the "x-ext-authz: allow"
curl -v -H "x-ext-authz: allow" \
    -H "Host: httpbin-1.test" \
    "${INGRESS_ENDPOINT}:80/headers"

curl -v -H "x-ext-authz: allow" \
    -H "Host: httpbin-2.test" \
    "${INGRESS_ENDPOINT}:80/headers"

# These respond with 403 since no x-ext-authz: allow is present in header
# incorrect value passed in header

curl -v -H "x-ext-authz: random-value" \
    -H "Host: httpbin-1.test" \
    "${INGRESS_ENDPOINT}:80/headers"

curl -v -H "x-ext-authz: random-value" \
    -H "Host: httpbin-2.test" \
    "${INGRESS_ENDPOINT}:80/headers"

### empty x-ext-authz - returns 403
curl -H "Host: httpbin-1.test" \
    "${INGRESS_ENDPOINT}:80/headers"

curl -H "Host: httpbin-2.test" \
    "${INGRESS_ENDPOINT}:80/headers"

################################################################################
# Cleanup
################################################################################
# Delete the application related components
kubectl -n httpbin-1 delete -f https://raw.githubusercontent.com/istio/istio/1.16.1/samples/extauthz/local-ext-authz.yaml
kubectl -n httpbin-2 delete -f https://raw.githubusercontent.com/istio/istio/1.16.1/samples/extauthz/local-ext-authz.yaml

# Delete the EnvoyFilter
kubectl -n httpbin-1 delete -f filter.yaml
kubectl -n httpbin-2 delete -f filter.yaml

# Delete the Gateway and the VirtualService
kubectl -n httpbin-1 delete -f gw-vs-httpbin-1.yaml
kubectl -n httpbin-2 delete -f gw-vs-httpbin-2.yaml

# Delete istio-cni NetworkAttachmentDefinition
kubectl -n httpbin-1 delete network-attachment-definition istio-cni
kubectl -n httpbin-2 delete network-attachment-definition istio-cni

# Delete the namespaces
kubectl delete ns httpbin-1 httpbin-2

unset INGRESS_ENDPOINT