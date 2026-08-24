package main

import (
	"testing"

	"github.com/ardnew/appium-agent/command"
)

func TestRebootDeviceExitsBeforeAppiumLaunch(t *testing.T) {
	if !exitsAfterDeviceOperation(&command.Model{RebootDevice: true}) {
		t.Fatal("reboot-device command should exit before Appium configuration validation and launch")
	}
	if !exitsAfterDeviceOperation(&command.Model{CycleUSB: true}) {
		t.Fatal("cycle-usb command should exit before Appium configuration validation and launch")
	}
	if exitsAfterDeviceOperation(new(command.Model)) {
		t.Fatal("ordinary Appium command should continue to configuration validation and launch")
	}
}
