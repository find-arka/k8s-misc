# create a cluster in "us-west-1"

```bash
export CLUSTER=test-acm-cross-cluster
export CURRENT_CONTEXT=test-acm-cross-cluster

export CLUSTER_REGION=us-west-1
export CA_REGION=us-east-1
```

```bash
eksctl create cluster --name "${CLUSTER}" --region "${CLUSTER_REGION}" --tags "created-by=${USER},team=${TEAM},purpose=customer-support" --vpc-cidr=192.168.0.0/21
```

# rename context
```bash
kubectl config rename-context \
    "${USER}@${CLUSTER}.${CLUSTER_REGION}.eksctl.io" \
    "${CURRENT_CONTEXT}"
```

# install cert-manager

[docs](https://cert-manager.io/docs/installation/helm/)

```bash
CERT_MANAGER_VERSION=v1.10.0
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --version ${CERT_MANAGER_VERSION} \
    --set installCRDs=true \
    --kube-context ${CURRENT_CONTEXT} \
    --wait
```

# Verify status
```bash
echo "Verify Deployment in ${CURRENT_CONTEXT}"
kubectl --context ${CURRENT_CONTEXT} -n cert-manager \
        rollout status deploy/cert-manager;
```

# Re-use existing CA for test
```bash
export GLOO_MESH_CA_ARN="arn:aws:acm-pca:us-east-1:<REDACTED>:certificate-authority/<REDACTED>"
export ISTIO_CA_ARN="arn:aws:acm-pca:us-east-1:<REDACTED>:certificate-authority/<REDACTED>"
```

# Re-using the IAM Policy which has access to the above CAs
```bash
export POLICY_ARN="arn:aws:iam::<REDACTED>:policy/AWSPCAIssuerPolicy-arka"
```

# Policy details for reference-

> My CA (1 root , 2 subordinate - 1 for istio, 1 for Gloo Mesh) lives in `us-east-1`
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "awspcaissuer",
      "Action": [
        "acm-pca:DescribeCertificateAuthority",
        "acm-pca:GetCertificate",
        "acm-pca:IssueCertificate"
      ],
      "Effect": "Allow",
      "Resource": [
        "${GLOO_MESH_CA_ARN}",
        "${ISTIO_CA_ARN}"
        ]
    }
  ]
}
````

# Install PCA Issuer
```bash
# Currently, we are installing the plugin in the same namespace as cert-manager
export PCA_NAMESPACE=cert-manager
# latest version https://github.com/cert-manager/aws-privateca-issuer/releases
export AWSPCA_ISSUER_TAG=v1.2.2

# Enable the IAM OIDC Provider for the EKS cluster
eksctl utils associate-iam-oidc-provider \
    --cluster=${CLUSTER} \
    --region=${CLUSTER_REGION} \
    --approve;

# Create IAM role bound to a service account which would be used by the AWS PCA Issuer
eksctl create iamserviceaccount --cluster=${CLUSTER} \
    --region=${CLUSTER_REGION} \
    --namespace=${PCA_NAMESPACE} \
    --attach-policy-arn=${POLICY_ARN} \
    --override-existing-serviceaccounts \
    --tags "created-by=${USER},team=${TEAM},purpose=customer-support" \
    --name=aws-pca-issuer \
    --role-name "ServiceAccountRolePrivateCA-${CLUSTER}" \
    --approve;

# Install AWS Private CA Issuer Plugin in the cluster
# https://github.com/cert-manager/aws-privateca-issuer/#setup
helm repo add awspca https://cert-manager.github.io/aws-privateca-issuer
helm repo update
helm upgrade --install aws-pca-issuer awspca/aws-privateca-issuer \
    --namespace ${PCA_NAMESPACE} \
    --set image.tag=${AWSPCA_ISSUER_TAG} \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-pca-issuer \
    --kube-context ${CURRENT_CONTEXT} \
    --wait;

# Verify status
kubectl --context ${CURRENT_CONTEXT} -n ${PCA_NAMESPACE} \
    rollout status deploy/aws-pca-issuer-aws-privateca-issuer;
```

# Create Issuer
```bash
cat << EOF | kubectl apply --context ${CURRENT_CONTEXT} -f -
apiVersion: awspca.cert-manager.io/v1beta1
kind: AWSPCAClusterIssuer
metadata:
  name: aws-pca-cluster-issuer-gloo-mesh-${CLUSTER}
spec:
  arn: ${GLOO_MESH_CA_ARN}
  region: ${CA_REGION}
EOF
```

# Create a namespace and create a `Certificate`
`kubectl --context $CURRENT_CONTEXT create namespace gloo-mesh;`

# create a cert with the help of the Issuer
```bash
cat << EOF | kubectl apply --context $CURRENT_CONTEXT -f -
kind: Certificate
apiVersion: cert-manager.io/v1
metadata:
  name: gloo-mesh-agent-$CURRENT_CONTEXT
  namespace: gloo-mesh
spec:
  commonName: gloo-mesh-agent-$CURRENT_CONTEXT
  dnsNames:
    # Must match the cluster name used in the helm chart install
    - "${CLUSTER}"
  duration: 8760h # 365 days
# ---------------- Issuer for Gloo Mesh certs ---------------------------
  issuerRef:
    group: awspca.cert-manager.io
    kind: AWSPCAClusterIssuer
    name: aws-pca-cluster-issuer-gloo-mesh-${CLUSTER}
# ---------------- Issuer for Gloo Mesh certs ---------------------------
  renewBefore: 360h # 15 days
  secretName: gloo-mesh-agent-$CURRENT_CONTEXT-tls-cert
  usages:
    - server auth
    - client auth
  privateKey:
    algorithm: "RSA"
    size: 2048
EOF
```

## Verify that the cert got created
```bash
kubectl -n gloo-mesh get Certificate gloo-mesh-agent-$CURRENT_CONTEXT
```

success output-
```bash
NAME                                     READY   SECRET                                            AGE
gloo-mesh-agent-test-acm-cross-cluster   True    gloo-mesh-agent-test-acm-cross-cluster-tls-cert   60s
```

# Extract the cert from the K8s secret
```bash
kubectl --context ${CURRENT_CONTEXT} get secret -n gloo-mesh \
 "gloo-mesh-agent-${CURRENT_CONTEXT}-tls-cert" -o yaml | yq -r '.data."tls.crt"' | base64 -d > tls-crt-${CURRENT_CONTEXT}.pem
```

# verify that it's created by the expected Issuer
```
openssl x509 -noout -text -in "tls-crt-${CURRENT_CONTEXT}.pem"
```

Inspect Expected value in Issuer-
```
        Issuer: C = US, O = Solo.io, OU = Consulting, ST = MA, CN = Intermediate CA Gloo-Mesh, L = Boston
        Validity
            Not Before: Nov  4 16:17:40 2022 GMT
            Not After : Nov  4 17:17:39 2023 GMT
```

# Test with AWSPCAIssuer

### create a 'test-namespace'
```bash
kubectl --context $CURRENT_CONTEXT create namespace test-namespace
```

### Create the AWSPCAIssuer object
```bash
cat << EOF | kubectl apply --context $CURRENT_CONTEXT -f -
apiVersion: awspca.cert-manager.io/v1beta1
kind: AWSPCAIssuer
metadata:
  name: issuer-test-namespace
  namespace: test-namespace
spec:
  arn: ${GLOO_MESH_CA_ARN}
  region: ${CA_REGION}
EOF
```

### create a cert with the help of the Issuer
```bash
cat << EOF | kubectl apply --context $CURRENT_CONTEXT -f -
kind: Certificate
apiVersion: cert-manager.io/v1
metadata:
  name: gloo-mesh-agent-$CURRENT_CONTEXT
  namespace: test-namespace
spec:
  commonName: gloo-mesh-agent-$CURRENT_CONTEXT
  dnsNames:
    # Must match the cluster name used in the helm chart install
    - "${CLUSTER}"
  duration: 8760h # 365 days
# ---------------- Issuer for Gloo Mesh certs ---------------------------
  issuerRef:
    group: awspca.cert-manager.io
    kind: AWSPCAIssuer
    name: issuer-test-namespace
# ---------------- Issuer for Gloo Mesh certs ---------------------------
  renewBefore: 360h # 15 days
  secretName: gloo-mesh-agent-$CURRENT_CONTEXT-tls-cert-test-namespace
  usages:
    - server auth
    - client auth
  privateKey:
    algorithm: "RSA"
    size: 2048
EOF
```

### Verify that the cert got created
```bash
kubectl -n test-namespace get Certificate gloo-mesh-agent-$CURRENT_CONTEXT
```

success output:
```bash
NAME                                     READY   SECRET                                                           AGE
gloo-mesh-agent-test-acm-cross-cluster   True    gloo-mesh-agent-test-acm-cross-cluster-tls-cert-test-namespace   50s
```

### Extract the cert from the K8s secret
```bash
kubectl --context ${CURRENT_CONTEXT} get secret -n test-namespace \
  "gloo-mesh-agent-${CURRENT_CONTEXT}-tls-cert-test-namespace" \
  -o yaml | yq -r '.data."tls.crt"' | base64 -d > tls-crt-test-namespace-${CURRENT_CONTEXT}.pem
```

### verify that it's created by the expected Issuer
```
openssl x509 -noout -text -in "tls-crt-test-namespace-${CURRENT_CONTEXT}.pem"
```

Inspect Expected value in Issuer-
```
        Issuer: C = US, O = Solo.io, OU = Consulting, ST = MA, CN = Intermediate CA Gloo-Mesh, L = Boston
        Validity
            Not Before: Nov  4 17:20:18 2022 GMT
            Not After : Nov  4 18:20:17 2023 GMT
```
