// Copyright 2019 The prometheus-operator Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package framework

import (
	"context"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
)

func MakeSecretWithCert(kubeClient kubernetes.Interface, ns, name, keyKey, certKey, caKey string,
	keyBytes, certBytes, caBytes []byte) *corev1.Secret {

	secret := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: ns},
		Type:       corev1.SecretType("Opaque"),
		Data:       map[string][]byte{},
	}

	if keyBytes != nil {
		secret.Data[keyKey] = keyBytes
	}

	if certBytes != nil {
		secret.Data[certKey] = certBytes
	}

	if caBytes != nil {
		secret.Data[caKey] = caBytes
	}

	return secret
}

func CreateSecretWithCert(kubeClient kubernetes.Interface, certBytes, keyBytes []byte, ns, name string) error {

	secret := MakeSecretWithCert(kubeClient, ns, name, "tls.key", "tls.crt", "", keyBytes, certBytes, nil)
	_, err := kubeClient.CoreV1().Secrets(ns).Create(context.TODO(), secret, metav1.CreateOptions{})

	return err
}
