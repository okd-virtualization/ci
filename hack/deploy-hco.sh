#!/usr/bin/env bash

set -euxo pipefail

TARGET_NAMESPACE=${TARGET_NAMESPACE:-kubevirt-hyperconverged}
HCO_UNSTABLE=${HCO_UNSTABLE:-false}
HCO_MANIFESTS_SUFFIX=""

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
