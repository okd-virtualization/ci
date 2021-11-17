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

echo "creating catalogsource, operator group, and subscription"
oc create namespace ${TARGET_NAMESPACE}
oc apply -f ${SCRIPT_DIR}/../manifests/catalog-unstable.yaml
oc apply -n ${TARGET_NAMESPACE} -f ${SCRIPT_DIR}/../manifests/virtualization.yaml

echo "waiting for HyperConverged operator to become ready"
"$SCRIPT_DIR"/wait-for-hco.sh
