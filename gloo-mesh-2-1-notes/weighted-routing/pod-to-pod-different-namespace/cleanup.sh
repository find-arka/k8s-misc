echo; echo "Deleting the ServiceAccount, Service, Deployment & NetworkAttachmentDefinition -"; echo
for CURRENT_CONTEXT in ${REMOTE_CONTEXT1} ${REMOTE_CONTEXT2}
do
    echo; echo "context ${CURRENT_CONTEXT}"; echo
    kubectl --context ${CURRENT_CONTEXT} --namespace client-namespace delete sa sleep
    kubectl --context ${CURRENT_CONTEXT} --namespace client-namespace delete svc sleep
    kubectl --context ${CURRENT_CONTEXT} --namespace client-namespace delete deploy sleep

    kubectl --context ${CURRENT_CONTEXT} --namespace server-namespace delete sa nginx
    kubectl --context ${CURRENT_CONTEXT} --namespace server-namespace delete svc nginx
    kubectl --context ${CURRENT_CONTEXT} --namespace server-namespace delete deploy nginx-deployment-a
    kubectl --context ${CURRENT_CONTEXT} --namespace server-namespace delete deploy nginx-deployment-b

    kubectl --context ${CURRENT_CONTEXT} --namespace client-namespace delete network-attachment-definition istio-cni
    kubectl --context ${CURRENT_CONTEXT} --namespace server-namespace delete network-attachment-definition istio-cni
done

echo; echo "Deleting the Workspace & WorkspaceSettings -"; echo
for NAMESPACE in "client-namespace" "server-namespace"
do
    echo; echo "Deleting GM workspace config for: ${NAMESPACE}"; echo
    kubectl -n gloo-mesh --context ${MGMT_CONTEXT} delete workspace ${NAMESPACE}
    kubectl -n ${NAMESPACE} --context ${MGMT_CONTEXT} delete workspacesettings ${NAMESPACE}
done

echo; echo "Deleting the Namespaces -"; echo
for CURRENT_CONTEXT in ${MGMT_CONTEXT} ${REMOTE_CONTEXT1} ${REMOTE_CONTEXT2}
do
    echo; echo "context ${CURRENT_CONTEXT}"; echo
    kubectl --context ${CURRENT_CONTEXT} delete namespace client-namespace
    kubectl --context ${CURRENT_CONTEXT} delete namespace server-namespace
done
