#!/bin/bash
# https://docs.solo.io/gloo-mesh-enterprise/latest/setup/installation/istio/gm_managed_istio/gloo_mesh_managed/#ilcm-openshift
export MGMT=drew-ocp-cluster3
export CLUSTER1=drew-ocp-cluster1
export CLUSTER2=drew-ocp-cluster2

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
done

#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#- Install Istio Discovery
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# https://support.solo.io/hc/en-us/articles/4414409064596
# istio-1.15
export REPO=<Please get the repo from https://support.solo.io/hc/en-us/articles/4414409064596>
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

curl -0L https://raw.githubusercontent.com/solo-io/gloo-mesh-use-cases/main/gloo-mesh/istio-install/gm-managed/gm-istiod-openshift.yaml > gm-istiod.yaml
envsubst < gm-istiod.yaml > gm-istiod-values.yaml
open gm-istiod-values.yaml

# Manual Todos for now
# add the following in "pilot.k8s.env" the end manually for now:
                # # Reload cacerts when cert-manager changes it #todo- add automated replacement
                # - name: AUTO_RELOAD_PLUGIN_CERTS
                #   value: "false"
# Also, set the outboundTrafficPolicy to REGISTRY_ONLY
kubectl apply -f gm-istiod-values.yaml --context $MGMT_CONTEXT

# verify istio operator is running in gm-iop-1-15
# verify istiod is running in istio-system

#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#- Install Istio e-w gateways
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
curl -0L https://raw.githubusercontent.com/solo-io/gloo-mesh-use-cases/main/gloo-mesh/istio-install/gm-managed/gm-ew-gateway.yaml > gm-ew-gateway.yaml

envsubst < gm-ew-gateway.yaml > gm-ew-gateway-values.yaml
open gm-ew-gateway-values.yaml
# ^ change the following if you wish to deploy in a different namespace- namespace: gloo-mesh-gateways

kubectl apply -f gm-ew-gateway-values.yaml --context $MGMT_CONTEXT

#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#- Install Istio Ingress gateway
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
curl -0L https://raw.githubusercontent.com/solo-io/gloo-mesh-use-cases/main/gloo-mesh/istio-install/gm-managed/gm-ingress-gateway.yaml > gm-ingress-gateway.yaml

envsubst < gm-ingress-gateway.yaml > gm-ingress-gateway-values.yaml
open gm-ingress-gateway-values.yaml

# ^ change the following if you wish to deploy in a different namespace- namespace: gloo-mesh-gateways

kubectl apply -f gm-ingress-gateway-values.yaml --context $MGMT_CONTEXT

for CURRENT_CONTEXT in ${REMOTE_CONTEXT1} ${REMOTE_CONTEXT2}
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
kubectl --context ${CURRENT_CONTEXT} -n kube-system get daemonsets istio-cni-node
# Expected:
# NAME             DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR            AGE
# istio-cni-node   6         6         6       6            6           kubernetes.io/os=linux   44m
