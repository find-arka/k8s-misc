istioctl --context ${REMOTE_CONTEXT1} pc secret \
    -n bookinfo-frontends deploy/productpage-v1 -o json | \
    jq '[.dynamicActiveSecrets[] | select(.name == "default")][0].secret.tlsCertificate.certificateChain.inlineBytes' -r | \
    base64 -d | \
    openssl x509 -noout -text
