kubectl --context ${MGMT_CONTEXT} -n gloo-mesh \
port-forward deploy/gloo-mesh-mgmt-server 9091 & PID=$!
sleep 3
curl -s http://localhost:9091/metrics | grep relay_push_clients_connected
curl -s http://localhost:9091/metrics | grep relay_pull_clients_connected
kill $PID
