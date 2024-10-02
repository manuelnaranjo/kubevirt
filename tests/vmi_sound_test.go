/*
 * This file is part of the KubeVirt project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Copyright 2021 Red Hat, Inc.
 *
 */

package tests_test

import (
	"context"
	"fmt"

	expect "github.com/google/goexpect"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	v1 "kubevirt.io/api/core/v1"
	"kubevirt.io/client-go/kubecli"

	"kubevirt.io/kubevirt/tests/console"
	"kubevirt.io/kubevirt/tests/decorators"
	"kubevirt.io/kubevirt/tests/framework/kubevirt"
	"kubevirt.io/kubevirt/tests/libvmifact"
	"kubevirt.io/kubevirt/tests/libwait"
	"kubevirt.io/kubevirt/tests/testsuite"
)

var _ = Describe("[crit:medium][vendor:cnv-qe@redhat.com][level:component][sig-compute] Sound", decorators.SigCompute, func() {

	var virtClient kubecli.KubevirtClient

	BeforeEach(func() {
		virtClient = kubevirt.Client()
	})

	Describe("[crit:medium][vendor:cnv-qe@redhat.com][level:component] A VirtualMachineInstance with default sound support", func() {

		It("should create an ich9 sound device on empty model", func() {
			vmi, err := createSoundVMI(virtClient, "test-model-empty")
			Expect(err).ToNot(HaveOccurred())
			vmi = libwait.WaitUntilVMIReady(vmi, console.LoginToCirros)
			checkAudioDevice(vmi, "ich9")
		})
	})

})

func createSoundVMI(virtClient kubecli.KubevirtClient, soundDevice string) (*v1.VirtualMachineInstance, error) {
	randomVmi := libvmifact.NewCirros()
	if soundDevice != "" {
		model := soundDevice
		if soundDevice == "test-model-empty" {
			model = ""
		}
		randomVmi.Spec.Domain.Devices.Sound = &v1.SoundDevice{
			Name:  "test-audio-device",
			Model: model,
		}
	}
	return virtClient.VirtualMachineInstance(testsuite.NamespaceTestDefault).Create(context.Background(), randomVmi, metav1.CreateOptions{})
}

func checkAudioDevice(vmi *v1.VirtualMachineInstance, name string) {
	// Audio device: Intel Corporation 82801I (ICH9 Family) HD Audio Controller
	deviceId := "8086:293e"
	cmdCheck := fmt.Sprintf("lspci | grep %s\n", deviceId)

	err := console.SafeExpectBatch(vmi, []expect.Batcher{
		&expect.BSnd{S: "\n"},
		&expect.BExp{R: console.PromptExpression},
		&expect.BSnd{S: cmdCheck},
		&expect.BExp{R: ".*8086.*"},
	}, 15)
	Expect(err).ToNot(HaveOccurred(), "Console command timeout")
}
