NAMESPACE=weighted-routing-multicluster-space
DEPLOYMENT_NAME=sleep
VIRTUAL_DESTINATION_NAME=weighted-routing-multicluster-space

kubectl -n $NAMESPACE port-forward deployments/$DEPLOYMENT_NAME 15000:15000 &
PID=$!
sleep 3
echo
curl -s localhost:15000/clusters | grep $VIRTUAL_DESTINATION_NAME | grep instance- | grep ":priority"
echo
kill $PID

istioctl pc endpoints -n "${NAMESPACE}" "deploy/${DEPLOYMENT_NAME}" | grep "${VIRTUAL_DESTINATION_NAME}" | grep instance
