#!/usr/bin/env bash

set -euxo pipefail

TARGET_NAMESPACE=${TARGET_NAMESPACE:-kubevirt-hyperconverged}
HCO_UNSTABLE=${HCO_UNSTABLE:-false}
HCO_MANIFESTS_SUFFIX=""
ROOK_VERSION=${ROOK_VERSION:-v1.7.8}
# TODO: properly do this on openshift-ci config with an additional step
TUNE_GCP_CONF=${TUNE_GCP_CONF:-true}
CEPH_CLUSTER=${CEPH_CLUSTER:-my-cluster}

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

if [ "$TUNE_GCP_CONF" = "true" ]; then
    echo "adding 3 worker nodes with 2 disks in zone f"
    oc patch -n openshift-machine-api $(oc get machinesets -n openshift-machine-api -o name | grep worker-f) --type=json  -p '[ { "op": "add", "path": /spec/template/spec/providerSpec/value/disks/-, "value": {"autoDelete": true, "boot": false, "labels": null, "sizeGb": 128, "type": "pd-ssd"} }, { "op": "replace", "path": /spec/replicas, "value": 1 } ]'
    echo "free the additional disk for ceph"
    # TODO: check if we can start with a blank disk
    oc apply -f ${SCRIPT_DIR}/99-worker-format-sdb.yaml
    echo "wait for the infra to be ready"
    ./hack/retry.sh 360 10 "oc get -n openshift-machine-api $(oc get machinesets -n openshift-machine-api -o name | grep worker-f) -o jsonpath='{ .status.readyReplicas }' | grep '1'"
    ./hack/retry.sh 360 10 "oc get -n openshift-machine-api $(oc get machinesets -n openshift-machine-api -o name | grep worker-f) -o jsonpath='{ .status.availableReplicas }' | grep '1'"
fi


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
oc create -f rook/cluster/examples/kubernetes/ceph/crds.yaml -f rook/cluster/examples/kubernetes/ceph/common.yaml
oc create -f rook/cluster/examples/kubernetes/ceph/operator-openshift.yaml
# oc create -f rook/cluster/examples/kubernetes/ceph/cluster.yaml
# oc create -f rook/cluster/examples/kubernetes/ceph/csi/rbd/storageclass.yaml
# Settings for a test cluster where redundancy is not configured. Requires only a single node.
# TODO: try with a 3 nodes cluster
oc create -f rook/cluster/examples/kubernetes/ceph/cluster-test.yaml
oc create -f rook/cluster/examples/kubernetes/ceph/csi/rbd/storageclass-test.yaml

echo "waiting for rook.io with Ceph to become ready and health"
./hack/retry.sh 60 10 "oc get CephCluster -n rook-ceph ${CEPH_CLUSTER} -o jsonpath='{ .status.phase }' | grep 'Ready'"
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
