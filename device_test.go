package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/ardnew/appium-agent/command"
	"github.com/ardnew/appium-agent/config"
)

func TestIOSDeviceRebootAndWait(t *testing.T) {
	var calls [][]string
	responses := [][]byte{
		nil,
		[]byte(`[{"udid":"device-1"}]`),
		[]byte(`[]`),
		[]byte(`{"deviceList":[{"Udid":"device-1"}]}`),
		[]byte(`[]`),
		[]byte(`[{"udid":"another-device"},{"udid":"device-1"}]`),
	}
	run := func(_ context.Context, arg ...string) ([]byte, error) {
		calls = append(calls, append([]string(nil), arg...))
		response := responses[0]
		responses = responses[1:]
		return response, nil
	}

	var out bytes.Buffer
	device := iosDevice{
		run: run,
		reload: func(_ context.Context, _ io.Writer) error {
			t.Fatal("reload called after automatic tunnel reconnection")
			return nil
		},
		out:                   &out,
		pollInterval:          time.Millisecond,
		automaticStartTimeout: 20 * time.Millisecond,
	}
	if err := device.rebootAndWait(context.Background(), "device-1"); err != nil {
		t.Fatalf("rebootAndWait() error = %v", err)
	}

	wantCalls := [][]string{
		{"reboot", "--udid=device-1"},
		{"tunnel", "ls", "--udid=device-1"},
		{"tunnel", "ls", "--udid=device-1"},
		{"list", "--details"},
		{"tunnel", "ls", "--udid=device-1"},
		{"tunnel", "ls", "--udid=device-1"},
	}
	if !reflect.DeepEqual(calls, wantCalls) {
		t.Fatalf("calls = %#v, want %#v", calls, wantCalls)
	}
	if !strings.Contains(out.String(), "Device tunnel reconnected.") {
		t.Fatalf("output = %q, want reconnect confirmation", out.String())
	}
}

func TestIOSDeviceReloadsTunnelAfterAutomaticStartTimeout(t *testing.T) {
	tunnelQueries := 0
	reloadCalls := 0
	run := func(_ context.Context, arg ...string) ([]byte, error) {
		switch arg[0] {
		case "reboot":
			return nil, nil
		case "list":
			return []byte(`{"deviceList":[{"Udid":"device-1"}]}`), nil
		case "tunnel":
			tunnelQueries++
			switch {
			case tunnelQueries == 1:
				return []byte(`[{"udid":"device-1"}]`), nil
			case tunnelQueries == 2 || reloadCalls == 0:
				return []byte(`[]`), nil
			default:
				return []byte(`[{"udid":"device-1"}]`), nil
			}
		default:
			return nil, fmt.Errorf("unexpected ios command: %v", arg)
		}
	}

	var out bytes.Buffer
	device := iosDevice{
		run: run,
		reload: func(_ context.Context, _ io.Writer) error {
			reloadCalls++
			return nil
		},
		out:                   &out,
		pollInterval:          time.Millisecond,
		automaticStartTimeout: time.Nanosecond,
	}
	if err := device.rebootAndWait(context.Background(), "device-1"); err != nil {
		t.Fatalf("rebootAndWait() error = %v", err)
	}
	if reloadCalls != 1 {
		t.Fatalf("reload calls = %d, want 1", reloadCalls)
	}
	if !strings.Contains(out.String(), tunnelReloadCommand) {
		t.Fatalf("output = %q, want tunnel reload command", out.String())
	}
}

func TestIOSDeviceRebootFailureStopsBeforeTunnelWait(t *testing.T) {
	wantErr := errors.New("reboot failed")
	callCount := 0
	device := iosDevice{
		run: func(_ context.Context, _ ...string) ([]byte, error) {
			callCount++
			return nil, wantErr
		},
		out: new(bytes.Buffer),
	}

	err := device.rebootAndWait(context.Background(), "device-1")
	if !errors.Is(err, wantErr) {
		t.Fatalf("rebootAndWait() error = %v, want %v", err, wantErr)
	}
	if callCount != 1 {
		t.Fatalf("command calls = %d, want 1", callCount)
	}
}

func TestIOSDeviceWaitForReconnectTimesOut(t *testing.T) {
	device := iosDevice{
		run: func(_ context.Context, _ ...string) ([]byte, error) {
			return []byte(`[]`), nil
		},
		out:          new(bytes.Buffer),
		pollInterval: time.Millisecond,
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Millisecond)
	defer cancel()

	err := device.waitForTunnelState(ctx, "device-1", true)
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("waitForTunnelState() error = %v, want deadline exceeded", err)
	}
}

func TestIOSDeviceTunnelAvailableRequiresMatchingUDID(t *testing.T) {
	device := iosDevice{
		run: func(_ context.Context, _ ...string) ([]byte, error) {
			return []byte(`[{"udid":"another-device"}]`), nil
		},
	}

	available, err := device.tunnelAvailable(context.Background(), "device-1")
	if err != nil {
		t.Fatalf("tunnelAvailable() error = %v", err)
	}
	if available {
		t.Fatal("tunnelAvailable() = true for a different device")
	}
}

func TestTargetDeviceUDID(t *testing.T) {
	tests := []struct {
		name    string
		target  string
		want    string
		wantErr bool
	}{
		{name: "hardware identifier", target: "id=device-1", want: "device-1"},
		{name: "device name", target: "Test iPad", wantErr: true},
		{name: "empty identifier", target: "id=", wantErr: true},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			cfg := &config.Model{Env: config.Env{
				config.NewVar("target-device", "d", "target_dest", config.String, test.target),
			}}
			got, err := targetDeviceUDID(cfg, new(command.Model), true)
			if (err != nil) != test.wantErr {
				t.Fatalf("targetDeviceUDID() error = %v, wantErr %t", err, test.wantErr)
			}
			if got != test.want {
				t.Fatalf("targetDeviceUDID() = %q, want %q", got, test.want)
			}
		})
	}
}

func TestTargetDeviceUDIDUsesAppiumConfigWhenNoConfigFlagWasGiven(t *testing.T) {
	root := t.TempDir()
	configPath := filepath.Join(root, "etc", "appium", "config.env")
	if err := os.MkdirAll(filepath.Dir(configPath), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(configPath, []byte("export target_dest='id=config-device'\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("target_dest", "id=environment-device")
	t.Setenv(command.AppiumdConfigIdent, "")

	cfg := &config.Model{Env: config.Env{
		config.NewVar("target-device", "d", "target_dest", config.String, "id=compiled-device"),
	}}
	cmd := &command.Model{ScriptPath: filepath.Join(root, "libexec", "appiumd.zsh")}

	got, err := targetDeviceUDID(cfg, cmd, false)
	if err != nil {
		t.Fatalf("targetDeviceUDID() error = %v", err)
	}
	if got != "config-device" {
		t.Fatalf("targetDeviceUDID() = %q, want config-device", got)
	}
}

func TestTargetDeviceUDIDUsesGeneratedConfigModel(t *testing.T) {
	t.Setenv("target_dest", "id=environment-device")
	cfg := &config.Model{Env: config.Env{
		config.NewVar("target-device", "d", "target_dest", config.String, "id=flag-device"),
	}}

	got, err := targetDeviceUDID(cfg, new(command.Model), true)
	if err != nil {
		t.Fatalf("targetDeviceUDID() error = %v", err)
	}
	if got != "flag-device" {
		t.Fatalf("targetDeviceUDID() = %q, want flag-device", got)
	}
}

func TestConfiguredTargetDeviceUsesExplicitAppiumConfig(t *testing.T) {
	root := t.TempDir()
	defaultPath := filepath.Join(root, "etc", "appium", "config.env")
	explicitPath := filepath.Join(t.TempDir(), "selected.env")
	if err := os.MkdirAll(filepath.Dir(defaultPath), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(defaultPath, []byte("export target_dest='id=default-device'\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(explicitPath, []byte("export target_dest=\"id=explicit-device\"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv(command.AppiumdConfigIdent, explicitPath)

	cmd := &command.Model{ScriptPath: filepath.Join(root, "libexec", "appiumd.zsh")}
	got, err := configuredTargetDevice(cmd)
	if err != nil {
		t.Fatalf("configuredTargetDevice() error = %v", err)
	}
	if got != "id=explicit-device" {
		t.Fatalf("configuredTargetDevice() = %q, want id=explicit-device", got)
	}
}
