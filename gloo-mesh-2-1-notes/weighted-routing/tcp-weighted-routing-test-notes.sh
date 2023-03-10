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
one Fri 10 Mar 2023 16:58:26 EST
one Fri 10 Mar 2023 16:58:27 EST
one Fri 10 Mar 2023 16:58:29 EST
two Fri 10 Mar 2023 16:58:30 EST
two Fri 10 Mar 2023 16:58:31 EST
one Fri 10 Mar 2023 16:58:32 EST
one Fri 10 Mar 2023 16:58:33 EST
one Fri 10 Mar 2023 16:58:34 EST
one Fri 10 Mar 2023 16:58:35 EST
one Fri 10 Mar 2023 16:58:36 EST
