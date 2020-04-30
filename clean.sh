#!/bin/bash

oc delete namespace minio
oc delete namespace observatorium
oc delete namespace spoke-example-app

oc delete clusterrole/prometheus-operator
oc delete clusterrolebinding/prometheus-operator
