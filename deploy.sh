#!/bin/bash

oc create namespace minio
oc create namespace observatorium

#FIXME: make this a secret.yaml
oc -n observatorium create secret generic tls-certs \
    --from-file certs/server.pem \
    --from-file certs/server.key \
    --from-file certs/ca.pem

oc apply -f environments/dev/manifests/
oc expose svc/observatorium-xyz-observatorium-api-gateway -n observatorium

observatoriu_svc_ip=`oc get svc/observatorium-xyz-observatorium-api-gateway -n observatorium \
    | tr -s " " | tail -1 | cut -d" " -f3`

echo "
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    prometheusK8s:
      remoteWrite:
        - url: "http://$observatoriu_svc_ip:8080/api/metrics/v1/write"
          writeRelabelConfigs:
          - sourceLabels: [__name__]
            replacement: cluster-monitoring-operator [no-TLS]
            targetLabel: cluster
          tlsConfig:
            insecureSkipVerify: true
" | oc apply -f -

#echo "
#apiVersion: v1
#kind: ConfigMap
#metadata:
#  name: cluster-monitoring-config
#  namespace: openshift-monitoring
#data:
#  config.yaml: |
#    prometheusK8s:
#      remoteWrite:
#        - url: "https://$observatoriu_svc_ip:8080/api/metrics/v1/write"
#          writeRelabelConfigs:
#          - sourceLabels: [__name__]
#            replacement: seal18_OS_cluster # this is the name of the cluster
#            targetLabel: cluster
#          tlsConfig:
#            cert_file: client.crt
#            key_file: client.key
#            insecureSkipVerify: true
#" | oc apply -f -
#
oc scale --replicas=1 statefulset --all -n openshift-monitoring; \
    oc scale --replicas=1 deployment --all -n openshift-monitoring
