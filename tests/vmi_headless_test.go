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
 * Copyright 2017, 2018 Red Hat, Inc.
 *
 */

package tests_test

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"time"

	"kubevirt.io/kubevirt/pkg/pointer"
	"kubevirt.io/kubevirt/tests/framework/kubevirt"
	"kubevirt.io/kubevirt/tests/framework/matcher"
	"kubevirt.io/kubevirt/tests/libnode"
	"kubevirt.io/kubevirt/tests/libvmops"

	virt_api "kubevirt.io/kubevirt/pkg/virt-api"

	"kubevirt.io/kubevirt/tests/decorators"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"

	v1 "kubevirt.io/api/core/v1"
	"kubevirt.io/client-go/kubecli"
	kvcorev1 "kubevirt.io/client-go/kubevirt/typed/core/v1"

	"kubevirt.io/kubevirt/tests"
	"kubevirt.io/kubevirt/tests/console"
	"kubevirt.io/kubevirt/tests/libnet"
	"kubevirt.io/kubevirt/tests/libvmifact"
)

var _ = Describe("[rfe_id:609][sig-compute]VMIheadless", decorators.SigCompute, func() {

	var virtClient kubecli.KubevirtClient
	var vmi *v1.VirtualMachineInstance

	BeforeEach(func() {
		virtClient = kubevirt.Client()

		vmi = libvmifact.NewAlpine()
	})

	Describe("[rfe_id:609]Creating a VirtualMachineInstance", func() {

		Context("with headless", func() {

			BeforeEach(func() {
				vmi.Spec.Domain.Devices.AutoattachGraphicsDevice = pointer.P(false)
			})

			It("[test_id:738][posneg:negative]should not connect to VNC", func() {
				vmi = libvmops.RunVMIAndExpectLaunch(vmi, 30)

				_, err := virtClient.VirtualMachineInstance(vmi.ObjectMeta.Namespace).VNC(vmi.ObjectMeta.Name)

				Expect(err.Error()).To(Equal("No graphics devices are present."), "vnc should not connect on headless VM")
			})

			It("[test_id:709][posneg:positive]should connect to console", func() {
				vmi = libvmops.RunVMIAndExpectLaunch(vmi, 30)

				By("checking that console works")
				Expect(console.LoginToAlpine(vmi)).To(Succeed())
			})

		})

		Context("without headless", func() {

			It("[test_id:714][posneg:negative]should have one vnc graphic device in xml", func() {
				vmi = libvmops.RunVMIAndExpectLaunch(vmi, 30)

				runningVMISpec, err := tests.GetRunningVMIDomainSpec(vmi)
				Expect(err).ToNot(HaveOccurred(), "should get vmi spec without problem")

				vncCount := 0
				for _, gr := range runningVMISpec.Devices.Graphics {
					if strings.ToLower(gr.Type) == "vnc" {
						vncCount += 1
					}
				}
				Expect(vncCount).To(Equal(1), "should have exactly one VNC device")
			})

			It("[Serial] multiple HTTP calls should re-use connections and not grow the number of open connections in virt-launcher", Serial, func() {
				getHandlerConnectionCount := func() int {
					cmd := []string{"bash", "-c", fmt.Sprintf("ss -ntlap | grep %d | wc -l", virt_api.DefaultConsoleServerPort)}
					stdout, stderr, err := libnode.ExecuteCommandOnNodeThroughVirtHandler(vmi.Status.NodeName, cmd)
					Expect(err).ToNot(HaveOccurred())
					Expect(stderr).To(BeEmpty())

					stdout = strings.TrimSpace(stdout)
					stdout = strings.ReplaceAll(stdout, "\n", "")

					handlerCons, err := strconv.Atoi(stdout)
					Expect(err).ToNot(HaveOccurred())

					return handlerCons
				}

				getClientCalls := func(vmi *v1.VirtualMachineInstance) []func() {
					vmiInterface := virtClient.VirtualMachineInstance(vmi.Namespace)
					expectNoErr := func(err error) {
						ExpectWithOffset(2, err).ToNot(HaveOccurred())
					}

					return []func(){
						func() {
							_, err := vmiInterface.GuestOsInfo(context.Background(), vmi.Name)
							expectNoErr(err)
						},
						func() {
							_, err := vmiInterface.FilesystemList(context.Background(), vmi.Name)
							expectNoErr(err)
						},
						func() {
							_, err := vmiInterface.UserList(context.Background(), vmi.Name)
							expectNoErr(err)
						},
						func() {
							_, err := vmiInterface.VNC(vmi.Name)
							expectNoErr(err)
						},
						func() {
							_, err := vmiInterface.SerialConsole(vmi.Name, &kvcorev1.SerialConsoleOptions{ConnectionTimeout: 30 * time.Second})
							expectNoErr(err)
						},
					}
				}

				By("Running the VMI")
				vmi = libvmifact.NewFedora(libnet.WithMasqueradeNetworking())
				vmi = libvmops.RunVMIAndExpectLaunch(vmi, 30)

				By("VMI has the guest agent connected condition")
				Eventually(matcher.ThisVMI(vmi), 240*time.Second, 2*time.Second).Should(matcher.HaveConditionTrue(v1.VirtualMachineInstanceAgentConnected), "should have agent connected condition")
				origHandlerCons := getHandlerConnectionCount()

				By("Making multiple requests")
				const numberOfRequests = 20
				clientCalls := getClientCalls(vmi)
				for i := 0; i < numberOfRequests; i++ {
					for _, clientCallFunc := range clientCalls {
						clientCallFunc()
					}
					time.Sleep(200 * time.Millisecond)
				}

				By("Expecting the number of connections to not grow")
				Expect(getHandlerConnectionCount()-origHandlerCons).To(BeNumerically("<=", len(clientCalls)), "number of connections is not expected to grow")
			})

		})

	})

})
