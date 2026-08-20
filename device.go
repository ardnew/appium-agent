package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/ardnew/appium-agent/command"
	"github.com/ardnew/appium-agent/config"
)

const (
	deviceRebootTimeout       = 10 * time.Minute
	tunnelPollInterval        = time.Second
	automaticTunnelStartDelay = 20 * time.Second
	tunnelReloadCommand       = "/opt/fsds/bin/reload-ios-tunnel"
	launchdContextCommand     = "sudo /usr/local/bin/launchctl-context fsds"
)

type iosCommand func(context.Context, ...string) ([]byte, error)
type tunnelReloader func(context.Context, io.Writer) error

type iosDevice struct {
	run                   iosCommand
	reload                tunnelReloader
	out                   io.Writer
	pollInterval          time.Duration
	automaticStartTimeout time.Duration
}

func newIOSDevice(out io.Writer) iosDevice {
	return iosDevice{
		run: func(ctx context.Context, arg ...string) ([]byte, error) {
			output, err := exec.CommandContext(ctx, "ios", arg...).Output()
			var exitErr *exec.ExitError
			if errors.As(err, &exitErr) {
				if stderr := strings.TrimSpace(string(exitErr.Stderr)); stderr != "" {
					return output, fmt.Errorf("%w: %s", err, stderr)
				}
			}
			return output, err
		},
		reload: func(ctx context.Context, out io.Writer) error {
			cmd := exec.CommandContext(ctx, tunnelReloadCommand)
			cmd.Stdout = out
			cmd.Stderr = out
			return cmd.Run()
		},
		out:                   out,
		pollInterval:          tunnelPollInterval,
		automaticStartTimeout: automaticTunnelStartDelay,
	}
}

func rebootTargetDevice(
	ctx context.Context,
	cfg *config.Model,
	cmd *command.Model,
	generatedConfig bool,
	out io.Writer,
) error {
	udid, err := targetDeviceUDID(cfg, cmd, generatedConfig)
	if err != nil {
		return err
	}
	return newIOSDevice(out).rebootAndWait(ctx, udid)
}

func targetDeviceUDID(
	cfg *config.Model, cmd *command.Model, generatedConfig bool,
) (string, error) {
	target, found := cfg.Env.Get(func(v *config.Var) bool {
		return v.Ident == "target_dest" || v.Flag == "target-device"
	})
	if !found {
		return "", errors.New("target-device configuration not found")
	}

	value := target.String()
	if !generatedConfig {
		var err error
		if value, err = configuredTargetDevice(cmd); err != nil {
			return "", err
		}
	}
	value = strings.TrimSpace(value)
	udid, found := strings.CutPrefix(value, "id=")
	if !found || strings.TrimSpace(udid) == "" {
		return "", fmt.Errorf("target-device must identify hardware as id=<UDID>, got %q", value)
	}
	return udid, nil
}

func configuredTargetDevice(cmd *command.Model) (string, error) {
	inherited, inheritedSet := os.LookupEnv("target_dest")

	scriptPath := cmd.ScriptPath
	if resolved, err := filepath.EvalSymlinks(scriptPath); err == nil {
		scriptPath = resolved
	}
	defaultPath := filepath.Join(
		filepath.Dir(filepath.Dir(scriptPath)), "etc", "appium", "config.env",
	)

	paths := make([]string, 0, 2)
	if path := strings.TrimSpace(os.Getenv(command.AppiumdConfigIdent)); path != "" {
		paths = append(paths, path)
	}
	if len(paths) == 0 || paths[0] != defaultPath {
		paths = append(paths, defaultPath)
	}

	for _, path := range paths {
		file, err := os.Open(path)
		if err != nil {
			continue // appiumd.zsh also skips configuration files that are not readable.
		}
		value, defined, readErr := readTargetDevice(file, inherited, inheritedSet)
		_ = file.Close()
		if readErr != nil {
			return "", fmt.Errorf("read target-device from Appium configuration %q: %w", path, readErr)
		}
		if !defined {
			return "", fmt.Errorf("target-device is undefined by Appium configuration %q", path)
		}
		return value, nil
	}

	if inheritedSet {
		return inherited, nil
	}
	return "", fmt.Errorf("target-device is undefined: no readable Appium configuration found")
}

func readTargetDevice(r io.Reader, inherited string, inheritedSet bool) (string, bool, error) {
	value, defined := inherited, inheritedSet
	scanner := bufio.NewScanner(r)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		fields := strings.Fields(line)
		if len(fields) > 0 && fields[0] == "unset" {
			for _, field := range fields[1:] {
				if field == "target_dest" {
					value, defined = "", false
				}
			}
			continue
		}

		assignment := strings.TrimSpace(strings.TrimPrefix(line, "export "))
		name, raw, found := strings.Cut(assignment, "=")
		if !found || strings.TrimSpace(name) != "target_dest" {
			continue
		}
		var err error
		if value, err = parseTargetAssignment(raw); err != nil {
			return "", false, err
		}
		defined = true
	}
	if err := scanner.Err(); err != nil {
		return "", false, err
	}
	return value, defined, nil
}

func parseTargetAssignment(raw string) (string, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return "", nil
	}

	switch raw[0] {
	case '\'':
		if end := strings.IndexByte(raw[1:], '\''); end >= 0 {
			end++
			if trailing := strings.TrimSpace(raw[end+1:]); trailing == "" || strings.HasPrefix(trailing, "#") {
				return raw[1:end], nil
			}
		}
	case '"':
		for end, escaped := 1, false; end < len(raw); end++ {
			switch {
			case escaped:
				escaped = false
			case raw[end] == '\\':
				escaped = true
			case raw[end] == '"':
				trailing := strings.TrimSpace(raw[end+1:])
				if trailing != "" && !strings.HasPrefix(trailing, "#") {
					break
				}
				return strconv.Unquote(raw[:end+1])
			}
		}
	default:
		if fields := strings.Fields(raw); len(fields) > 0 {
			return fields[0], nil
		}
	}
	return "", fmt.Errorf("unsupported target_dest assignment %q", raw)
}

func (d iosDevice) rebootAndWait(ctx context.Context, udid string) error {
	fmt.Fprintf(d.out, "Rebooting iOS device %s...\n", udid)
	if _, err := d.run(ctx, "reboot", "--udid="+udid); err != nil {
		return fmt.Errorf("ios reboot: %w", err)
	}

	fmt.Fprintln(d.out, "Waiting for the device tunnel to disconnect...")
	if err := d.waitForTunnelState(ctx, udid, false); err != nil {
		return fmt.Errorf("wait for device tunnel to disconnect: %w", err)
	}

	fmt.Fprintln(d.out, "Waiting for the device to reconnect over USB...")
	if err := d.waitForDevice(ctx, udid); err != nil {
		return fmt.Errorf("wait for device USB connection: %w", err)
	}

	fmt.Fprintln(d.out, "Waiting for the device tunnel to reconnect...")
	automaticTimeout := d.automaticStartTimeout
	if automaticTimeout <= 0 {
		automaticTimeout = automaticTunnelStartDelay
	}
	automaticCtx, cancel := context.WithTimeout(ctx, automaticTimeout)
	err := d.waitForTunnelState(automaticCtx, udid, true)
	cancel()
	if err != nil && ctx.Err() != nil {
		return fmt.Errorf("wait for device tunnel to reconnect: %w", err)
	}
	if err != nil {
		fmt.Fprintf(d.out, "Device tunnel did not reconnect within %s; running %s...\n",
			automaticTimeout, tunnelReloadCommand)
		if err = d.reload(ctx, d.out); err != nil {
			return fmt.Errorf("reload device tunnel with %s: %w; retry by entering the GUI launchd "+
				"context with %q, then run %q", tunnelReloadCommand, err,
				launchdContextCommand, tunnelReloadCommand)
		}
		fmt.Fprintln(d.out, "Waiting for the reloaded device tunnel...")
		if err = d.waitForTunnelState(ctx, udid, true); err != nil {
			return fmt.Errorf("wait for reloaded device tunnel: %w", err)
		}
	}

	fmt.Fprintln(d.out, "Device tunnel reconnected.")
	return nil
}

func (d iosDevice) waitForDevice(ctx context.Context, udid string) error {
	interval := d.pollInterval
	if interval <= 0 {
		interval = tunnelPollInterval
	}

	for {
		available, err := d.deviceAvailable(ctx, udid)
		if err == nil && available {
			return nil
		}

		timer := time.NewTimer(interval)
		select {
		case <-ctx.Done():
			timer.Stop()
			if err != nil {
				return fmt.Errorf("%w (last device query: %v)", ctx.Err(), err)
			}
			return ctx.Err()
		case <-timer.C:
		}
	}
}

func (d iosDevice) waitForTunnelState(ctx context.Context, udid string, connected bool) error {
	interval := d.pollInterval
	if interval <= 0 {
		interval = tunnelPollInterval
	}

	for {
		available, err := d.tunnelAvailable(ctx, udid)
		if err == nil && available == connected {
			return nil
		}

		timer := time.NewTimer(interval)
		select {
		case <-ctx.Done():
			timer.Stop()
			if err != nil {
				return fmt.Errorf("%w (last tunnel query: %v)", ctx.Err(), err)
			}
			return ctx.Err()
		case <-timer.C:
		}
	}
}

func (d iosDevice) tunnelAvailable(ctx context.Context, udid string) (bool, error) {
	out, err := d.run(ctx, "tunnel", "ls", "--udid="+udid)
	if err != nil {
		return false, err
	}

	var tunnels []struct {
		UDID string `json:"udid"`
	}
	if err = json.Unmarshal(out, &tunnels); err != nil {
		return false, fmt.Errorf("decode ios tunnel ls output: %w", err)
	}
	for _, tunnel := range tunnels {
		if tunnel.UDID == udid {
			return true, nil
		}
	}
	return false, nil
}

func (d iosDevice) deviceAvailable(ctx context.Context, udid string) (bool, error) {
	out, err := d.run(ctx, "list", "--details")
	if err != nil {
		return false, err
	}

	var devices struct {
		DeviceList []struct {
			UDID string `json:"Udid"`
		} `json:"deviceList"`
	}
	if err = json.Unmarshal(out, &devices); err != nil {
		return false, fmt.Errorf("decode ios list output: %w", err)
	}
	for _, device := range devices.DeviceList {
		if device.UDID == udid {
			return true, nil
		}
	}
	return false, nil
}
