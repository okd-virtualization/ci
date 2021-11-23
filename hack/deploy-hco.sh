#!/usr/bin/env bash

set -euxo pipefail

TARGET_NAMESPACE=${TARGET_NAMESPACE:-kubevirt-hyperconverged}
HCO_UNSTABLE=${HCO_UNSTABLE:-false}
HCO_MANIFESTS_SUFFIX=""
ROOK_VERSION=${ROOK_VERSION:-v1.8.2}
CEPH_CLUSTER=${CEPH_CLUSTER:-rook-ceph}

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

echo "creating catalogsource, operator group, and subscription"
oc create namespace ${TARGET_NAMESPACE}
if [ "$HCO_UNSTABLE" = "true" ]; then
    HCO_MANIFESTS_SUFFIX="-unstable"
    oc apply -f ${SCRIPT_DIR}/../manifests/catalog${HCO_MANIFESTS_SUFFIX}.yaml
fi
oc apply -n ${TARGET_NAMESPACE} -f ${SCRIPT_DIR}/../manifests/virtualization${HCO_MANIFESTS_SUFFIX}.yaml

echo "waiting for HyperConverged operator to become ready"
"$SCRIPT_DIR"/wait-for-hco.sh

echo "deploy rook.io with Ceph"
git clone --single-branch --branch ${ROOK_VERSION} https://github.com/rook/rook.git
oc create -f rook/deploy/examples/crds.yaml
oc create -f rook/deploy/examples/common.yaml
oc create -f rook/deploy/examples/operator-openshift.yaml
# oc create -f rook/deploy/examples/cluster.yaml
# Settings for a test cluster based on top of cloud instances.
# TODO: try with nodes with two disks without the need for cloud instances
oc create -f rook/deploy/examples/cluster-on-pvc.yaml
oc create -f rook/deploy/examples/csi/rbd/storageclass.yaml

echo "waiting for rook.io with Ceph to become ready and health"
./hack/retry.sh 180 10 "oc get CephCluster -n rook-ceph ${CEPH_CLUSTER} -o jsonpath='{ .status.phase }' | grep 'Ready'"
./hack/retry.sh 60 10 "oc get CephCluster -n rook-ceph ${CEPH_CLUSTER} -o jsonpath='{ .status.state }' | grep 'Created'"
./hack/retry.sh 90 10 "oc get CephCluster -n rook-ceph ${CEPH_CLUSTER} -o jsonpath='{ .status.ceph.health }' | grep HEALTH_OK"

echo "start a Fedora 35 VM with Ceph by rook.io"
oc apply -f ${SCRIPT_DIR}/vm_fedora35_rookceph.yaml
if [ "$TUNE_GCP_CONF" = "true" ]; then
    oc patch vm -n default fedora-35-test --type=json -p '[ { "op": "add", "path": /spec/template/spec/nodeSelector, "value": {"topology.kubernetes.io/zone": "us-central1-f"} } ]'
fi
oc patch vm -n default fedora-35-test --type=json  -p '[ { "op": "replace", "path": /spec/running, "value": true } ]'

./hack/retry.sh 180 10 "oc get vmi -n default fedora-35-test -o jsonpath='{ .status.phase }' | grep 'Running'"
oc get vmi -n default -o yaml fedora-35-test
