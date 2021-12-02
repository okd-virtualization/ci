#!/bin/bash

CMD=${CMD:-oc}

function RunCmd {
    cmd=$@
    echo "Command: $cmd"
    echo ""
    bash -c "$cmd"
    stat=$?
    if [ "$stat" != "0" ]; then
        echo "Command failed: $cmd Status: $stat"
    fi
}

function ShowOperatorSummary {

    local kind=$1
    local name=$2
    local namespace=$3

    echo ""
    echo "Status of Operator object: kind=$kind name=$name"
    echo ""

    QUERY="{range .status.conditions[*]}{.type}{'\t'}{.status}{'\t'}{.message}{'\n'}{end}" 
    if [ "$namespace" == "." ]; then
        RunCmd "$CMD get $kind $name -o=jsonpath=\"$QUERY\""
    else
        RunCmd "$CMD get $kind $name -n $namespace -o=jsonpath=\"$QUERY\""
    fi
}

cat <<EOF
=================================
     Start of HCO state dump         
=================================
EOF

if [ -n "${ARTIFACT_DIR}" ]; then
    cat <<EOF
==============================
executing kubevirt-must-gather
==============================

EOF
    mkdir -p ${ARTIFACT_DIR}/kubevirt-must-gather
    RunCmd "${CMD} adm must-gather --image=quay.io/kubevirt/must-gather:latest --dest-dir=${ARTIFACT_DIR}/kubevirt-must-gather"
    mkdir -p ${ARTIFACT_DIR}/origin-must-gather
    RunCmd "${CMD} adm must-gather --image=quay.io/openshift/origin-must-gather:latest --dest-dir=${ARTIFACT_DIR}/origin-must-gather"
    mkdir -p ${ARTIFACT_DIR}/rook-must-gather
    RunCmd "${CMD} adm must-gather --image=quay.io/ocs-dev/ocs-must-gather:latest --dest-dir=${ARTIFACT_DIR}/rook-must-gather"
fi

cat <<EOF
==========================
summary of operator status
==========================

EOF
NAMESPACE_ARG=$1
ROOK_NAMESPACE_ARG=$2
HCO_NAMESPACE=${NAMESPACE_ARG:-"kubevirt-hyperconverged"}
ROOK_NAMESPACE=${ROOK_NAMESPACE_ARG:-"rook-ceph"}
echo $1

RunCmd "${CMD} get pods -n ${HCO_NAMESPACE}"
RunCmd "${CMD} get subscription -n ${HCO_NAMESPACE} -o yaml"
RunCmd "${CMD} get deployment/hco-operator -n ${HCO_NAMESPACE} -o yaml"
RunCmd "${CMD} get hyperconvergeds -n ${HCO_NAMESPACE} kubevirt-hyperconverged -o yaml"

ShowOperatorSummary  hyperconvergeds.hco.kubevirt.io kubevirt-hyperconverged ${HCO_NAMESPACE}

RELATED_OBJECTS=`${CMD} get hyperconvergeds.hco.kubevirt.io kubevirt-hyperconverged -n ${HCO_NAMESPACE} -o go-template='{{range .status.relatedObjects }}{{if .namespace }}{{ printf "%s %s %s\n" .kind .name .namespace }}{{ else }}{{ printf "%s %s .\n" .kind .name }}{{ end }}{{ end }}'`

echo "${RELATED_OBJECTS}" | while read line; do 

    fields=( $line )
    kind=${fields[0]} 
    name=${fields[1]} 
    namespace=${fields[2]} 

    if [ "$kind" != "ConfigMap" ]; then
        ShowOperatorSummary $kind $name $namespace
    fi
done

cat <<EOF

======================
ClusterServiceVersions
======================
EOF

RunCmd "${CMD} get clusterserviceversions -n ${HCO_NAMESPACE}"
RunCmd "${CMD} get clusterserviceversions -n ${HCO_NAMESPACE} -o yaml"

cat <<EOF

============
InstallPlans
============
EOF

RunCmd "${CMD} get installplans -n ${HCO_NAMESPACE} -o yaml"

cat <<EOF

==============
OperatorGroups
==============
EOF

RunCmd "${CMD} get operatorgroups -n ${HCO_NAMESPACE} -o yaml"

cat <<EOF

========================
HCO operator related CRD
========================
EOF

echo "${RELATED_OBJECTS}" | while read line; do 

    fields=( $line )
    kind=${fields[0]} 
    name=${fields[1]} 
    namespace=${fields[2]} 

    if [ "$namespace" == "." ]; then
        echo "Related object: kind=$kind name=$name"
        RunCmd "$CMD get $kind $name -o json"
    else
        echo "Related object: kind=$kind name=$name namespace=$namespace"
        RunCmd "$CMD get $kind $name -n $namespace -o json"
    fi
done

cat <<EOF

========
HCO Pods
========

EOF

RunCmd "$CMD get pods -n ${HCO_NAMESPACE} -o json"

cat <<EOF

=================================
HyperConverged Operator pods logs
=================================
EOF

namespace=kubevirt-hyperconverged
RunCmd "$CMD logs -n $namespace -l name=hyperconverged-cluster-operator"

cat <<EOF

=================================
HyperConverged Webhook pods logs
=================================
EOF
RunCmd "$CMD logs -n $namespace -l name=hyperconverged-cluster-webhook"

cat <<EOF

============
Catalog logs
============
EOF

catalog_namespace=openshift-operator-lifecycle-manager
RunCmd "$CMD logs -n $catalog_namespace $($CMD get pods -n $catalog_namespace | grep catalog-operator | head -1 | awk '{ print $1 }')"


cat <<EOF

===============
HCO Deployments
===============

EOF

RunCmd "$CMD get deployments -n ${HCO_NAMESPACE} -o json"

cat <<EOF

=================
Rook Ceph Cluster
=================

EOF

RunCmd "$CMD get CephCluster -n ${ROOK_NAMESPACE} rook-ceph -o yaml"

cat <<EOF

====================
Rook Ceph Block Pool
====================

EOF

RunCmd "$CMD get CephBlockPool -n ${ROOK_NAMESPACE} replicapool -o yaml"

cat <<EOF

======================
Rook Ceph StorageClass
======================

EOF

RunCmd "$CMD get storageclass rook-ceph-block -o yaml"

cat <<EOF

==============
Rook Ceph Pods
==============

EOF

RunCmd "$CMD get pods -n ${ROOK_NAMESPACE}"

cat <<EOF

==============
Rook Pods Logs
==============

EOF

for p in $($CMD -n ${ROOK_NAMESPACE} get pods -o jsonpath='{.items[*].metadata.name}')
do
    for c in $($CMD -n ${ROOK_NAMESPACE} get pod ${p} -o jsonpath='{.spec.containers[*].name}')
    do
        echo "====== BEGIN logs from pod: ${p} ${c} ======"
	$CMD logs -n ${ROOK_NAMESPACE} -c ${c} ${p} || true
        echo "====== END logs from pod: ${p} ${c} ======"
    done
done

cat <<EOF
===============================
     End of HCO state dump    
===============================
EOF
