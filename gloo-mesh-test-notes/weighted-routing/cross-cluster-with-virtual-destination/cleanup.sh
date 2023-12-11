export NAMESPACE="weighted-routing-multicluster-space"
echo; echo "Deleting the ServiceAccount, Service, Deployment & NetworkAttachmentDefinition -"; echo
for CURRENT_CONTEXT in ${REMOTE_CONTEXT1} ${REMOTE_CONTEXT2}
do
    echo; echo "context ${CURRENT_CONTEXT}"; echo
    kubectl --context ${CURRENT_CONTEXT} --namespace $NAMESPACE delete sa sleep
    kubectl --context ${CURRENT_CONTEXT} --namespace $NAMESPACE delete deploy sleep

    kubectl --context ${CURRENT_CONTEXT} --namespace $NAMESPACE delete sa nginx
    kubectl --context ${CURRENT_CONTEXT} --namespace $NAMESPACE delete svc nginx
    kubectl --context ${CURRENT_CONTEXT} --namespace $NAMESPACE delete deploy nginx-deployment-a
    kubectl --context ${CURRENT_CONTEXT} --namespace $NAMESPACE delete deploy nginx-deployment-b

    kubectl --context ${CURRENT_CONTEXT} --namespace $NAMESPACE delete network-attachment-definition istio-cni
done

echo; echo "Deleting the Workspace & WorkspaceSettings -"; echo


echo; echo "Deleting GM workspace config for: ${NAMESPACE}"; echo
kubectl -n ${NAMESPACE} --context ${MGMT_CONTEXT} delete workspacesettings ${NAMESPACE}
kubectl -n gloo-mesh --context ${MGMT_CONTEXT} delete workspace ${NAMESPACE}

echo; echo "Deleting the Namespaces -"; echo
for CURRENT_CONTEXT in ${MGMT_CONTEXT} ${REMOTE_CONTEXT1} ${REMOTE_CONTEXT2}
do
    echo; echo "context ${CURRENT_CONTEXT}"; echo
    kubectl --context ${CURRENT_CONTEXT} delete namespace $NAMESPACE
done

unset NAMESPACE