#!/bin/bash

NAMESPACE="spoke-example-app"

oc create namespace minio
oc create namespace observatorium
oc create namespace $NAMESPACE

echo "========================================================================="
echo "                      deploying Observatorium                            "
echo "========================================================================="

#FIXME: make this a secret.yaml
oc -n observatorium create secret generic tls-certs \
    --from-file certs/server.pem \
    --from-file certs/server.key \
    --from-file certs/ca.pem

oc apply -f environments/dev/manifests/
oc expose svc/observatorium-xyz-observatorium-api-gateway -n observatorium

# expose svc/observatorium-xyz-observatorium-api-gateway
#sudo -- sh -c "echo $(minikube ip)  observatorium-xyz-observatorium-api-gateway-observatorium.apps-crc.testing >> /etc/hosts"
#echo "
#apiVersion: extensions/v1beta1
#kind: Ingress
#metadata:
#  name: observatorium-xyz-observatorium-api-gateway
#  namespace: observatorium
#spec:
#  rules:
#  - host: observatorium-xyz-observatorium-api-gateway-observatorium.apps-crc.testing
#    http:
#      paths:
#      - backend:
#          serviceName: observatorium-xyz-observatorium-api-gateway
#          servicePort: 8080
#        path: /
#" | oc apply -f -

echo "========================================================================="
echo "                      deploying example-app                              "
echo "========================================================================="

# deploy three instances of a simple example application, which listens and exposes metrics on port 8080
echo "
apiVersion: apps/v1
kind: Deployment
metadata:
  name: example-app
  namespace: $NAMESPACE
spec:
  replicas: 3
  selector:
    matchLabels:
      app: example-app
  template:
    metadata:
      labels:
        app: example-app
    spec:
      containers:
      - name: example-app
        image: fabxc/instrumented_app
        ports:
        - name: web
          containerPort: 8080
" | oc apply -f -

# deploy a service for example-app
echo "
kind: Service
apiVersion: v1
metadata:
  name: example-app
  namespace: $NAMESPACE
  labels:
    app: example-app
spec:
  selector:
    app: example-app
  ports:
  - name: web
    port: 8080
" | oc apply -f -

echo "========================================================================="
echo "                      deploying prometheus-operator                      "
echo "========================================================================="

# deploy ServiceMonitor (CRD) for the app
echo "
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: example-app
  namespace: $NAMESPACE
  labels:
    team: frontend
spec:
  selector:
    matchLabels:
      app: example-app
  endpoints:
  - port: web
" | oc apply -f -

## Enable RBAC rules for Prometheus pods
echo "
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prometheus-operator
  namespace: $NAMESPACE
" | oc apply -f -

echo "
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  name: prometheus
rules:
- apiGroups:
  - "*"
  resources:
  - "*"
  verbs: ["get", "list", "watch"]
- apiGroups:
  - "*"
  resources:
  - "*"
  verbs: ["get"]
- nonResourceURLs: ["/metrics"]
  verbs: ["get"]
" | oc apply -f -

#echo "
#apiVersion: rbac.authorization.k8s.io/v1
#kind: ClusterRole
#metadata:
#  labels:
#    app.kubernetes.io/component: controller
#    app.kubernetes.io/name: prometheus-operator
#    app.kubernetes.io/version: v0.38.0
#  name: prometheus-operator
#rules:
#- apiGroups:
#  - monitoring.coreos.com
#  resources:
#  - alertmanagers
#  - alertmanagers/finalizers
#  - prometheuses
#  - prometheuses/finalizers
#  - thanosrulers
#  - thanosrulers/finalizers
#  - servicemonitors
#  - podmonitors
#  - prometheusrules
#  verbs:
#  - '*'
#- apiGroups:
#  - apps
#  resources:
#  - statefulsets
#  verbs:
#  - '*'
#- apiGroups:
#  - ""
#  resources:
#  - configmaps
#  - secrets
#  verbs:
#  - '*'
#- apiGroups:
#  - ""
#  resources:
#  - pods
#  verbs:
#  - list
#  - delete
#- apiGroups:
#  - ""
#  resources:
#  - services
#  - services/finalizers
#  - endpoints
#  verbs:
#  - get
#  - create
#  - update
#  - delete
#- apiGroups:
#  - ""
#  resources:
#  - nodes
#  verbs:
#  - list
#  - watch
#- apiGroups:
#  - ""
#  resources:
#  - namespaces
#  verbs:
#  - get
#  - list
#  - watch
#" | oc apply -f -

echo "
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: prometheus-operator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus-operator
subjects:
- kind: ServiceAccount
  name: prometheus-operator
  namespace: $NAMESPACE
" | oc apply -f -

observatoriu_svc_ip=`oc get svc/observatorium-xyz-observatorium-api-gateway -n observatorium \
    | tr -s " " | tail -1 | cut -d" " -f3`

# deploy Prometheus CR
echo "
apiVersion: monitoring.coreos.com/v1
kind: Prometheus
metadata:
  name: prometheus
  namespace: $NAMESPACE
spec:
  serviceAccountName: prometheus
  serviceMonitorSelector:
    matchLabels:
      team: frontend
  resources:
    requests:
      memory: 400Mi
  enableAdminAPI: false
  remoteWrite:
  - url: "http://$observatoriu_svc_ip:8080/api/metrics/v1/write"
    writeRelabelConfigs:
    - sourceLabels: [__name__]
      replacement: prometheus-operator [no-TLS]
      targetLabel: cluster
    tlsConfig:
      insecureSkipVerify: true
" | oc apply -f -
#
##FIXME: are the "resources" ok?
## deploy prometheus operator
#echo "
#apiVersion: apps/v1
#kind: Deployment
#metadata:
#  labels:
#    app.kubernetes.io/component: controller
#    app.kubernetes.io/name: prometheus-operator
#    app.kubernetes.io/version: v0.38.0
#  name: prometheus-operator
#  namespace: $NAMESPACE
#spec:
#  replicas: 1
#  selector:
#    matchLabels:
#      app.kubernetes.io/component: controller
#      app.kubernetes.io/name: prometheus-operator
#  template:
#    metadata:
#      labels:
#        app.kubernetes.io/component: controller
#        app.kubernetes.io/name: prometheus-operator
#        app.kubernetes.io/version: v0.38.0
#    spec:
#      containers:
#      - args:
#        - --kubelet-service=kube-system/kubelet
#        - --logtostderr=true
#        - --config-reloader-image=jimmidyson/configmap-reload:v0.3.0
#        - --prometheus-config-reloader=quay.io/coreos/prometheus-config-reloader:v0.38.0
#        image: quay.io/coreos/prometheus-operator:v0.38.0
#        name: prometheus-operator
#        ports:
#        - containerPort: 8080
#          name: http
#        resources:
#          limits:
#            cpu: 200m
#            memory: 200Mi
#          requests:
#            cpu: 100m
#            memory: 100Mi
#        securityContext:
#          allowPrivilegeEscalation: false
#      nodeSelector:
#        beta.kubernetes.io/os: linux
#      securityContext:
#        runAsNonRoot: true
#        runAsUser: 65534
#      serviceAccountName: prometheus-operator
#" | oc apply -f -
#
# deploy prometheus operator
echo "
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app.kubernetes.io/component: controller
    app.kubernetes.io/name: prometheus-operator
    app.kubernetes.io/version: v0.38.0
  name: prometheus-operator
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/component: controller
      app.kubernetes.io/name: prometheus-operator
  template:
    metadata:
      labels:
        app.kubernetes.io/component: controller
        app.kubernetes.io/name: prometheus-operator
        app.kubernetes.io/version: v0.38.0
    spec:
      containers:
      - args:
        - --kubelet-service=kube-system/kubelet
        - --logtostderr=true
        - --config-reloader-image=jimmidyson/configmap-reload:v0.3.0
        - --prometheus-config-reloader=quay.io/coreos/prometheus-config-reloader:v0.38.0
        image: quay.io/coreos/prometheus-operator:v0.38.0
        name: prometheus-operator
        ports:
        - containerPort: 8080
          name: http
        securityContext:
          allowPrivilegeEscalation: false
      nodeSelector:
        beta.kubernetes.io/os: linux
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000620001
      serviceAccountName: prometheus-operator
" | oc apply -f -


