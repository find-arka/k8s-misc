##
# minimal check with 'istioctl pc secrets'
##
istioctl --context ${REMOTE_CONTEXT1} pc secrets -n bookinfo-frontends deploy/productpage-v1
istioctl --context ${REMOTE_CONTEXT2} pc secrets -n bookinfo-backends deploy/reviews-v3

##
# detailed check with pc secrets -o json
##
# cluster 1
istioctl --context ${REMOTE_CONTEXT1} pc secret \
    -n bookinfo-frontends deploy/productpage-v1 -o json | \
    jq '[.dynamicActiveSecrets[] | select(.name == "default")][0].secret.tlsCertificate.certificateChain.inlineBytes' -r | \
    base64 -d | \
    openssl x509 -noout -text

# cluster 2
istioctl --context ${REMOTE_CONTEXT2} pc secret \
    -n bookinfo-backends deploy/reviews-v3 -o json | \
    jq '[.dynamicActiveSecrets[] | select(.name == "default")][0].secret.tlsCertificate.certificateChain.inlineBytes' -r | \
    base64 -d | \
    openssl x509 -noout -text
