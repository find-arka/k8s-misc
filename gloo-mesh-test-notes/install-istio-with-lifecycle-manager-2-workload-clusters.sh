#!/bin/bash
# https://docs.solo.io/gloo-mesh-enterprise/latest/setup/installation/istio/gm_managed_istio/gloo_mesh_managed/#ilcm-openshift
export MGMT=drew-ocp-cluster3
export CLUSTER1=drew-ocp-cluster1
export CLUSTER2=arka-ocp-cluster1

export MGMT_CLUSTER=$MGMT
export REMOTE_CLUSTER1=$CLUSTER1
export REMOTE_CLUSTER2=$CLUSTER2

export MGMT_CONTEXT=$MGMT_CLUSTER
export REMOTE_CONTEXT1=$REMOTE_CLUSTER1
export REMOTE_CONTEXT2=$REMOTE_CLUSTER2

#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#- add-scc-to-group
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
for CURRENT_CONTEXT in ${REMOTE_CONTEXT1} ${REMOTE_CONTEXT2}
do
    echo; echo;
    echo "CURRENT_CONTEXT is $CURRENT_CONTEXT"
    oc adm policy add-scc-to-group anyuid system:serviceaccounts:istio-system --context $CURRENT_CONTEXT
    oc adm policy add-scc-to-group anyuid system:serviceaccounts:istio-operator --context $CURRENT_CONTEXT
    oc adm policy add-scc-to-group anyuid system:serviceaccounts:gm-iop-1-15 --context $CURRENT_CONTEXT
    oc adm policy add-scc-to-group anyuid system:serviceaccounts:gloo-mesh-gateways --context $CURRENT_CONTEXT
    oc adm policy add-scc-to-group anyuid system:serviceaccounts:istio-gateways --context $CURRENT_CONTEXT
done

#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#- Install Istio Discovery
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# https://support.solo.io/hc/en-us/articles/4414409064596
# istio-1.15
export REPO="IN THE SUPPORT LINK" 
export ISTIO_IMAGE=1.15.3-solo
export REVISION=1-15

# export ISTIO_REVISION=1-15
# export ISTIO_VERSION=1.15.3
# curl -L https://istio.io/downloadIstio | sh -

# validated env vars
echo "REPO=${REPO}"
echo "ISTIO_IMAGE=${ISTIO_IMAGE}"
echo "REVISION=${REVISION}"
echo "REMOTE_CLUSTER1=${REMOTE_CLUSTER1}"
echo "REMOTE_CLUSTER2=${REMOTE_CLUSTER2}"

# curl -0L https://raw.githubusercontent.com/solo-io/gloo-mesh-use-cases/main/gloo-mesh/istio-install/gm-managed/gm-istiod-openshift.yaml > gm-istiod.yaml
# doing one cluster at a time
export CLUSTER_NAME=$REMOTE_CLUSTER1
echo $CLUSTER_NAME

curl -0L https://raw.githubusercontent.com/solo-io/gloo-mesh-use-cases/main/gloo-mesh/istio-install/gm-managed/single-cluster/gm-istiod-openshift.yaml > gm-istiod.yaml
envsubst < gm-istiod.yaml > gm-istiod-values.yaml
open gm-istiod-values.yaml
# Manual steps for now
# 1. add the following in "pilot.k8s.env" the end manually for now:
                # # Reload cacerts when cert-manager changes it #todo- add automated replacement
                # - name: AUTO_RELOAD_PLUGIN_CERTS
                #   value: "false"
# 2. Also, set the outboundTrafficPolicy to REGISTRY_ONLY
# 3. Set profile: minimal
echo $MGMT_CONTEXT
kubectl apply -f gm-istiod-values.yaml --context $MGMT_CONTEXT

# Add the following under `spec.installations.revision.clusters` in the "gm-istiod-values.yaml" for adding clusters
#       - name: YOUR SECOND CLUSTER NAME
#         defaultRevision: true
# & then re-apply
# kubectl apply -f gm-istiod-values.yaml --context $MGMT_CONTEXT

# verify istio operator is running in gm-iop-1-15
# verify istiod is running in istio-system

#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#- Install Istio e-w gateways
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
curl -0L https://raw.githubusercontent.com/solo-io/gloo-mesh-use-cases/main/gloo-mesh/istio-install/gm-managed/gm-ew-gateway.yaml > gm-ew-gateway.yaml
envsubst < gm-ew-gateway.yaml > gm-ew-gateway-values.yaml
open gm-ew-gateway-values.yaml
# ^ 
# 1. change gloo-mesh-gateways to istio-gateways, if you wish to deploy gateways in the istio-gateways namespace
# 2. Edit the `clusters` and only have 1 cluster if you want to do this 1 at a time.

kubectl apply -f gm-ew-gateway-values.yaml --context $MGMT_CONTEXT

for CURRENT_CONTEXT in ${REMOTE_CLUSTER2}
do
cat <<EOF | oc --context ${CURRENT_CONTEXT} -n istio-gateways create -f -
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: istio-cni
EOF
done

# For future clusters, just edit the `GatewayLifecycleManager` yaml and add following in the spec.installations.revision.clusters
# open gm-ew-gateway-values.yaml
    #   - name: arka-ocp-cluster1
    #     activeGateway: true

#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#- Install Istio Ingress gateway
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

curl -0L https://raw.githubusercontent.com/solo-io/gloo-mesh-use-cases/main/gloo-mesh/istio-install/gm-managed/gm-ingress-gateway.yaml > gm-ingress-gateway.yaml
envsubst < gm-ingress-gateway.yaml > gm-ingress-gateway-values.yaml
open gm-ingress-gateway-values.yaml
# 1. change gloo-mesh-gateways to istio-gateways, if you wish to deploy gateways in the istio-gateways namespace
# 2. Edit the `clusters` and only have 1 cluster if you want to do this 1 at a time.
kubectl apply -f gm-ingress-gateway-values.yaml --context $MGMT_CONTEXT

# For future clusters, just edit the `GatewayLifecycleManager` yaml and add following in the spec.installations.revision.clusters
# open gm-ingress-gateway-values.yaml
    #   - name: arka-ocp-cluster1
    #     activeGateway: true
# kubectl apply -f gm-ingress-gateway-values.yaml --context $MGMT_CONTEXT


for CURRENT_CONTEXT in ${REMOTE_CLUSTER1}
do
    echo; echo;
    echo "CURRENT_CONTEXT is $CURRENT_CONTEXT"
    oc get projects --context $CURRENT_CONTEXT | grep iop
    oc get projects --context $CURRENT_CONTEXT | grep istio
    oc get projects --context $CURRENT_CONTEXT | grep gateways
done
# For example, the gm-iop-1-15, gloo-mesh-gateways, and istio-system projects are created


#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#- Verify that the Istio control plane pods are running
# iop - Operator revision project
# istio-system - Istiod project
# gloo-mesh-gateways - Istio Gateway project
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
for CURRENT_CONTEXT in ${REMOTE_CONTEXT1} ${REMOTE_CONTEXT2}
do
    echo; echo;
    echo $CURRENT_CONTEXT
    oc get all -n gm-iop-1-15 --context $CURRENT_CONTEXT
    oc get all -n istio-system --context $CURRENT_CONTEXT
    oc get all -n gloo-mesh-gateways --context $CURRENT_CONTEXT
done

# verify-
kubectl --context ${REMOTE_CONTEXT1} -n kube-system get daemonsets istio-cni-node
# Expected:
# NAME             DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR            AGE
# istio-cni-node   6         6         6       6            6           kubernetes.io/os=linux   44m
