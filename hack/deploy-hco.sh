#!/usr/bin/env bash

set -euxo pipefail

HCO_RELEASE=${HCO_RELEASE:-1.6.0}
TARGET_NAMESPACE=${TARGET_NAMESPACE:-kubevirt-hyperconverged}

function cleanup() {
    rv=$?
    if [ "x$rv" != "x0" ]; then
        echo "Error during deployment: exit status: $rv"
        make dump-state
        echo "*** HCO deployment failed ***"
    fi
    exit $rv
}

trap "cleanup" INT TERM EXIT

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

echo "creating catalogsource"
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: hco-unstable-catalog-source
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: quay.io/kubevirt/hyperconverged-cluster-index:${HCO_RELEASE}-unstable
  displayName: Kubevirt Hyperconverged Cluster Operator
  publisher: Kubevirt Project
EOF

echo "creating namespace"
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
    name: ${TARGET_NAMESPACE}
EOF

echo "creating operator group"
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
    name: kubevirt-hyperconverged-group
    namespace: ${TARGET_NAMESPACE}
EOF

echo "creating subscription"
oc create -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: kubevirt-hyperconverged
  namespace: "${TARGET_NAMESPACE}"
  labels:
    operators.coreos.com/kubevirt-hyperconverged.kubevirt-hyperconverged: ''
spec:
  channel: ${HCO_RELEASE}
  installPlanApproval: Automatic
  name: community-kubevirt-hyperconverged
  source: hco-unstable-catalog-source
  sourceNamespace: openshift-marketplace
EOF

echo "waiting for HyperConverged operator to become ready"
"$SCRIPT_DIR"/wait-for-hco.sh
