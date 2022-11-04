#!/bin/bash

set -e

# Note: Please feel free to edit the following section as per your need for the CA Subject details.
export COUNTRY="CA"
export ORGANIZATION="my-org.ca"
export ORGANIZATIONAL_UNIT="Consulting"
export STATE="ON"
export LOCALITY="Toronto"

# Note: Please feel free to edit the values for Validity time of the Root cert and the Subordinate cert.
export ROOT_CERT_VALIDITY_IN_DAYS=3650
export SUBORDINATE_CERT_VALIDITY_IN_DAYS=1825

echo
echo "###########################################################"
echo " Creating Root CA"
echo " Generated and managed by ACM"
echo "###########################################################"
cat <<EOF > ca_config_root_ca.json
{
   "KeyAlgorithm":"RSA_2048",
   "SigningAlgorithm":"SHA256WITHRSA",
   "Subject":{
      "Country":"${COUNTRY}",
      "Organization":"${ORGANIZATION}",
      "OrganizationalUnit":"${ORGANIZATIONAL_UNIT}",
      "State":"${STATE}",
      "Locality":"${LOCALITY}",
      "CommonName":"Root CA"
   }
}
EOF

echo
echo "[INFO] Creates the root private certificate authority (CA)."
# https://docs.aws.amazon.com/cli/latest/reference/acm-pca/create-certificate-authority.html
ROOT_CAARN=$(aws acm-pca create-certificate-authority \
     --certificate-authority-configuration file://ca_config_root_ca.json \
     --certificate-authority-type "ROOT" \
     --idempotency-token 01234567 \
     --output json \
     --tags Key=Name,Value=RootCA | jq -r '.CertificateAuthorityArn')
echo "[INFO] Sleeping for 15 seconds for CA creation to be completed..."
sleep 15
echo "[DEBUG] ARN of Root CA=${ROOT_CAARN}"

echo "[INFO] download Root CA CSR from AWS"
# https://docs.aws.amazon.com/cli/latest/reference/acm-pca/get-certificate-authority-csr.html
aws acm-pca get-certificate-authority-csr \
    --certificate-authority-arn "${ROOT_CAARN}" \
    --output text > root-ca.csr

echo "[INFO] Issue Root Certificate. Valid for ${ROOT_CERT_VALIDITY_IN_DAYS} days"
# https://docs.aws.amazon.com/cli/latest/reference/acm-pca/issue-certificate.html
ROOT_CERTARN=$(aws acm-pca issue-certificate \
    --certificate-authority-arn "${ROOT_CAARN}" \
    --csr fileb://root-ca.csr \
    --signing-algorithm "SHA256WITHRSA" \
    --template-arn arn:aws:acm-pca:::template/RootCACertificate/V1 \
    --validity Value=${ROOT_CERT_VALIDITY_IN_DAYS},Type="DAYS" \
    --idempotency-token 1234567 \
    --output json | jq -r '.CertificateArn')
echo "[INFO] Sleeping for 15 seconds for cert issuance to be completed..."
sleep 15
echo "[DEBUG] ARN of Root Certificate=${ROOT_CERTARN}"

echo "[INFO] Retrieves root certificate from private CA and save locally as root-ca.pem"
# https://docs.aws.amazon.com/cli/latest/reference/acm-pca/get-certificate.html
aws acm-pca get-certificate \
    --certificate-authority-arn "${ROOT_CAARN}" \
    --certificate-arn "${ROOT_CERTARN}" \
    --output text > root-ca.pem

echo "[INFO] Import the signed Private CA certificate for the CA specified by the ARN into ACM PCA"
# https://docs.aws.amazon.com/cli/latest/reference/acm-pca/import-certificate-authority-certificate.html
aws acm-pca import-certificate-authority-certificate \
    --certificate-authority-arn "${ROOT_CAARN}" \
    --certificate fileb://root-ca.pem
echo "-----------------------------------------------------------"
echo "ARN of Root CA is ${ROOT_CAARN}"
echo "-----------------------------------------------------------"

echo
echo "###########################################################"
echo " Create Intermediate CA for common-purpose"
echo " Generated and managed by ACM, signed by Root CA"
echo "###########################################################"
cat <<EOF > "ca_config_intermediate_ca_common-purpose.json"
{
"KeyAlgorithm":"RSA_2048",
"SigningAlgorithm":"SHA256WITHRSA",
"Subject":{
    "Country":"${COUNTRY}",
    "Organization":"${ORGANIZATION}",
    "OrganizationalUnit":"${ORGANIZATIONAL_UNIT}",
    "State":"${STATE}",
    "Locality":"${LOCALITY}",
    "CommonName":"Intermediate CA common-purpose"
}
}
EOF
echo "[INFO] Create the Subordinate/Intermediate private certificate authority (CA) for common-purpose"
# https://docs.aws.amazon.com/cli/latest/reference/acm-pca/create-certificate-authority.html
SUBORDINATE_CAARN=$(aws acm-pca create-certificate-authority \
    --certificate-authority-configuration file://ca_config_intermediate_ca_common-purpose.json \
    --certificate-authority-type "SUBORDINATE" \
    --idempotency-token 01234567 \
    --tags Key=Name,Value="SubordinateCA-common-purpose" | jq -r '.CertificateAuthorityArn')
echo "[INFO] Sleeping for 15 seconds for CA creation to be completed..."
sleep 15
echo "[DEBUG] ARN of Subordinate CA for common-purpose=${SUBORDINATE_CAARN}"

echo "[INFO] Download Intermediate CA CSR from AWS"
# https://docs.aws.amazon.com/cli/latest/reference/acm-pca/get-certificate-authority-csr.html
aws acm-pca get-certificate-authority-csr \
    --certificate-authority-arn "${SUBORDINATE_CAARN}" \
    --output text > "intermediate_ca_common-purpose.csr"

echo "[INFO] Issue Intermediate Certificate for common-purpose. Valid for ${SUBORDINATE_CERT_VALIDITY_IN_DAYS} days."
SUBORDINATE_CERTARN=$(aws acm-pca issue-certificate \
    --certificate-authority-arn "${ROOT_CAARN}" \
    --csr fileb://intermediate_ca_common-purpose.csr \
    --signing-algorithm "SHA256WITHRSA" \
    --template-arn arn:aws:acm-pca:::template/SubordinateCACertificate_PathLen3/V1 \
    --validity Value=${SUBORDINATE_CERT_VALIDITY_IN_DAYS},Type="DAYS" \
    --idempotency-token 1234567 \
    --output json | jq -r '.CertificateArn')
echo "[INFO] Sleeping for 15 seconds for cert issuance to be completed..."
sleep 15
echo "[DEBUG] ARN of Subordinate CA Certificate for common-purpose=${SUBORDINATE_CERTARN}"

echo "[INFO] Retrieve Intermediate certificate from private CA and save locally as intermediate-cert.pem"
aws acm-pca get-certificate \
    --certificate-authority-arn "${ROOT_CAARN}" \
    --certificate-arn "${SUBORDINATE_CERTARN}" \
    --output json | jq -r '.Certificate' > "intermediate-cert-common-purpose.pem"

echo "[INFO] Retrieve Intermediate certificate chain from private CA and save locally as intermediate-cert-chain.pem"
aws acm-pca get-certificate \
    --certificate-authority-arn "${ROOT_CAARN}" \
    --certificate-arn "${SUBORDINATE_CERTARN}" \
    --output json | jq -r '.CertificateChain' > "intermediate-cert-chain-common-purpose.pem"

echo "[INFO] Import the certificate into ACM PCA"
aws acm-pca import-certificate-authority-certificate \
    --certificate-authority-arn "${SUBORDINATE_CAARN}" \
    --certificate fileb://intermediate-cert-common-purpose.pem \
    --certificate-chain fileb://intermediate-cert-chain-common-purpose.pem
echo "-----------------------------------------------------------"
echo "ARN of common-purpose CA is ${SUBORDINATE_CAARN}"
echo "-----------------------------------------------------------"
