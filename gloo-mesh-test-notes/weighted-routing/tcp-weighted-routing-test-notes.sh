# Deploy sample tcp-echo v1 and v2
kubectl -n bookinfo-frontends apply -f https://raw.githubusercontent.com/istio/istio/release-1.17/samples/tcp-echo/tcp-echo-services.yaml

# Gateway, DestinationRule, VirtualService
kubectl -n bookinfo-frontends apply -f https://raw.githubusercontent.com/istio/istio/release-1.17/samples/tcp-echo/tcp-echo-all-v1.yaml

# Weight based VirtualService override (80-20)
kubectl -n bookinfo-frontends apply -f https://raw.githubusercontent.com/istio/istio/release-1.17/samples/tcp-echo/tcp-echo-20-v2.yaml

INGRESS_ENDPOINT="your-ingress-endpoint"
TCP_PORT_ON_INGRESS=31400

for i in {1..10}; do
    echo "$(date; sleep 1)" | nc "${INGRESS_ENDPOINT}" "${TCP_PORT_ON_INGRESS}"
done

# Output contains response from both v1 and v2 of tcp-echo
one Fri 17 Mar 2023 12:31:14 EDT
one Fri 17 Mar 2023 12:31:15 EDT
two Fri 17 Mar 2023 12:31:17 EDT
one Fri 17 Mar 2023 12:31:18 EDT
one Fri 17 Mar 2023 12:31:19 EDT
one Fri 17 Mar 2023 12:31:20 EDT
one Fri 17 Mar 2023 12:31:21 EDT
one Fri 17 Mar 2023 12:31:22 EDT
two Fri 17 Mar 2023 12:31:23 EDT
one Fri 17 Mar 2023 12:31:24 EDT

# Add "appProtocol: tcp"
kubectl -n bookinfo-frontends apply -f- <<EOF
apiVersion: v1
kind: Service
metadata:
  name: tcp-echo
  labels:
    app: tcp-echo
    service: tcp-echo
spec:
  ports:
  - name: tcp
  # --- Added "appProtocol: tcp" ---
    appProtocol: tcp
    port: 9000
  selector:
    app: tcp-echo
EOF

# Test with 100% v2 , 0% v1
kubectl -n bookinfo-frontends apply -f- <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: tcp-echo
spec:
  hosts:
  - "*"
  gateways:
  - tcp-echo-gateway
  tcp:
  - match:
    - port: 31400
    route:
    - destination:
        host: tcp-echo
        port:
          number: 9000
        subset: v1
      weight: 0
    - destination:
        host: tcp-echo
        port:
          number: 9000
        subset: v2
      weight: 100
EOF

for i in {1..10}; do
    echo "$(date; sleep 1)" | nc "${INGRESS_ENDPOINT}" "${TCP_PORT_ON_INGRESS}"
done

two Fri 17 Mar 2023 12:42:46 EDT
two Fri 17 Mar 2023 12:42:47 EDT
two Fri 17 Mar 2023 12:42:48 EDT
two Fri 17 Mar 2023 12:42:49 EDT
two Fri 17 Mar 2023 12:42:50 EDT
two Fri 17 Mar 2023 12:42:51 EDT
two Fri 17 Mar 2023 12:42:53 EDT
two Fri 17 Mar 2023 12:42:54 EDT
two Fri 17 Mar 2023 12:42:55 EDT
two Fri 17 Mar 2023 12:42:56 EDT


# Test with 100% v1 , 0% v2
kubectl -n bookinfo-frontends apply -f- <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: tcp-echo
spec:
  hosts:
  - "*"
  gateways:
  - tcp-echo-gateway
  tcp:
  - match:
    - port: 31400
    route:
    - destination:
        host: tcp-echo
        port:
          number: 9000
        subset: v1
      weight: 100
    - destination:
        host: tcp-echo
        port:
          number: 9000
        subset: v2
      weight: 0
EOF

for i in {1..10}; do
    echo "$(date; sleep 1)" | nc "${INGRESS_ENDPOINT}" "${TCP_PORT_ON_INGRESS}"
done

one Fri 17 Mar 2023 12:43:46 EDT
one Fri 17 Mar 2023 12:43:47 EDT
one Fri 17 Mar 2023 12:43:48 EDT
one Fri 17 Mar 2023 12:43:49 EDT
one Fri 17 Mar 2023 12:43:50 EDT
one Fri 17 Mar 2023 12:43:51 EDT
one Fri 17 Mar 2023 12:43:52 EDT
one Fri 17 Mar 2023 12:43:53 EDT
one Fri 17 Mar 2023 12:43:54 EDT
one Fri 17 Mar 2023 12:43:55 EDT

# verify that appProtocol is in place
kubectl -n bookinfo-frontends get svc tcp-echo -o yaml | yq .spec.ports
- appProtocol: tcp
  name: tcp
  port: 9000
  protocol: TCP
  targetPort: 9000
