### VirtualDestination, FailoverPolicy and RouteTable used

```yaml
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
```

### endpoints & priority check

```bash
NAMESPACE=weighted-routing-multicluster-space
DEPLOYMENT_NAME=sleep
VIRTUAL_DESTINATION_NAME=nginx-multicluster-a-b.global

# pc endpoints
istioctl pc endpoints  --context $REMOTE_CONTEXT1 -n "${NAMESPACE}" "deploy/${DEPLOYMENT_NAME}" | grep "${VIRTUAL_DESTINATION_NAME}" | grep instance

# priority check
kubectl --context $REMOTE_CONTEXT1 -n $NAMESPACE port-forward deployments/$DEPLOYMENT_NAME 15000:15000 &
PID=$!
sleep 10
echo
curl -s localhost:15000/clusters | grep $VIRTUAL_DESTINATION_NAME | grep instance- | grep ":priority"
echo
kill $PID
```

#### Output

##### endpoints
```bash
10.128.2.43:80                                          HEALTHY     OK                outbound|80|instance-a|nginx-multicluster-a-b.global
10.131.0.76:80                                          HEALTHY     OK                outbound|80|instance-b|nginx-multicluster-a-b.global
52.52.13.205:15443                                      HEALTHY     OK                outbound|80|instance-a|nginx-multicluster-a-b.global
52.52.13.205:15443                                      HEALTHY     OK                outbound|80|instance-b|nginx-multicluster-a-b.global
52.8.3.232:15443                                        HEALTHY     OK                outbound|80|instance-a|nginx-multicluster-a-b.global
52.8.3.232:15443                                        HEALTHY     OK                outbound|80|instance-b|nginx-multicluster-a-b.global
```

##### priority
```bash
outbound|80|instance-b|nginx-multicluster-a-b.global::10.131.0.76:80::priority::0
outbound|80|instance-b|nginx-multicluster-a-b.global::52.8.3.232:15443::priority::1
outbound|80|instance-b|nginx-multicluster-a-b.global::52.52.13.205:15443::priority::1
outbound|80|instance-a|nginx-multicluster-a-b.global::10.128.2.43:80::priority::0
outbound|80|instance-a|nginx-multicluster-a-b.global::52.8.3.232:15443::priority::1
outbound|80|instance-a|nginx-multicluster-a-b.global::52.52.13.205:15443::priority::1
```
