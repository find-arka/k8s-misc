echo; echo "Deleting the ServiceAccount, Service, Deployment & NetworkAttachmentDefinition -"; echo
for CURRENT_CONTEXT in ${REMOTE_CONTEXT1} ${REMOTE_CONTEXT2}
do
    echo; echo "context ${CURRENT_CONTEXT}"; echo
    kubectl --context ${CURRENT_CONTEXT} --namespace helmtest-weighted delete sa sleep
    kubectl --context ${CURRENT_CONTEXT} --namespace helmtest-weighted delete svc sleep
    kubectl --context ${CURRENT_CONTEXT} --namespace helmtest-weighted delete deploy sleep

    kubectl --context ${CURRENT_CONTEXT} --namespace helmtest-weighted delete sa nginx
    kubectl --context ${CURRENT_CONTEXT} --namespace helmtest-weighted delete svc nginx
    kubectl --context ${CURRENT_CONTEXT} --namespace helmtest-weighted delete deploy nginx-deployment-a
    kubectl --context ${CURRENT_CONTEXT} --namespace helmtest-weighted delete deploy nginx-deployment-b

    kubectl --context ${CURRENT_CONTEXT} --namespace helmtest-weighted delete network-attachment-definition istio-cni
done

echo; echo "Deleting the Workspace & WorkspaceSettings -"; echo
for NAMESPACE in "helmtest-weighted"
do
    echo; echo "Deleting GM workspace config for: ${NAMESPACE}"; echo
    kubectl -n gloo-mesh --context ${MGMT_CONTEXT} delete workspace ${NAMESPACE}
    kubectl -n ${NAMESPACE} --context ${MGMT_CONTEXT} delete workspacesettings ${NAMESPACE}
done

echo; echo "Deleting the Namespaces -"; echo
for CURRENT_CONTEXT in ${MGMT_CONTEXT} ${REMOTE_CONTEXT1} ${REMOTE_CONTEXT2}
do
    echo; echo "context ${CURRENT_CONTEXT}"; echo
    kubectl --context ${CURRENT_CONTEXT} delete namespace helmtest-weighted
done
