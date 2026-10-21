package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/ardnew/appium-agent/command"
	"github.com/ardnew/appium-agent/config"
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

func TestConfigurationExclusionsSeparateCalcAndDriverRequirements(t *testing.T) {
	t.Setenv(config.DefaultKeychainIdent, "test-keychain")
	t.Setenv(config.DefaultPasswordIdent, "test-password")
	cfg := new(config.Model)
	if err := cfg.Init(new(command.Model)); err != nil {
		t.Fatal(err)
	}
	if err := cfg.ValidateExcept(configurationExclusions(command.ModeFull)...); err == nil ||
		!strings.Contains(err.Error(), `"proj_source"`) {
		t.Fatalf("full mode error=%v, want missing Calculator source", err)
	}
	source, _ := cfg.Env.Get(func(v *config.Var) bool { return v.Ident == "proj_source" })
	if err := source.Set("/calc"); err != nil {
		t.Fatal(err)
	}
	calcBundle, _ := cfg.Env.Get(func(v *config.Var) bool { return v.Ident == "bundled_app" })
	if err := calcBundle.Set(""); err != nil {
		t.Fatal(err)
	}
	driverScheme, _ := cfg.Env.Get(func(v *config.Var) bool { return v.Ident == "test_driver_scheme" })
	if err := driverScheme.Set(""); err != nil {
		t.Fatal(err)
	}
	driverConfig, _ := cfg.Env.Get(func(v *config.Var) bool { return v.Ident == "test_config" })
	driverBundle, _ := cfg.Env.Get(func(v *config.Var) bool { return v.Ident == "bundled_drv" })
	if err := driverConfig.Set(""); err != nil {
		t.Fatal(err)
	}
	if err := driverBundle.Set(""); err != nil {
		t.Fatal(err)
	}
	if err := cfg.ValidateExcept(configurationExclusions(command.ModeFull)...); err != nil {
		t.Fatalf("Calculator-only mode requires no Driver selection: %v", err)
	}
	if err := cfg.ValidateExcept(configurationExclusions(command.ModeRelaunchTestDriver)...); err == nil ||
		!strings.Contains(err.Error(), `"test_driver_source"`) {
		t.Fatalf("Driver mode error=%v, want missing Driver source", err)
	}
	driverSource, _ := cfg.Env.Get(func(v *config.Var) bool { return v.Ident == "test_driver_source" })
	if err := driverSource.Set("/driver"); err != nil {
		t.Fatal(err)
	}
	if err := driverScheme.Set("FMPS Test Driver"); err != nil {
		t.Fatal(err)
	}
	if err := driverConfig.Set("Release"); err != nil {
		t.Fatal(err)
	}
	if err := driverBundle.Set("com.example.Driver"); err != nil {
		t.Fatal(err)
	}
	for _, ident := range []string{"proj_source", "target_app_ipa", "proj_scheme", "xcbuild_act", "proj_config", "bundled_app"} {
		v, _ := cfg.Env.Get(func(v *config.Var) bool { return v.Ident == ident })
		if err := v.Set(""); err != nil {
			t.Fatal(err)
		}
	}
	if err := cfg.ValidateExcept(configurationExclusions(command.ModeTestDriverOnly)...); err != nil {
		t.Fatalf("Driver-only mode requires no Calculator installation: %v", err)
	}
	for _, ident := range []string{"test_driver_source", "test_driver_scheme", "test_config", "bundled_drv"} {
		v, _ := cfg.Env.Get(func(v *config.Var) bool { return v.Ident == ident })
		if err := v.Set(""); err != nil {
			t.Fatal(err)
		}
	}
	if err := cfg.ValidateExcept(configurationExclusions(command.ModeRestart)...); err != nil {
		t.Fatalf("restart does not require either build source: %v", err)
	}
	ipa, _ := cfg.Env.Get(func(v *config.Var) bool { return v.Ident == "target_app_ipa" })
	app, _ := cfg.Env.Get(func(v *config.Var) bool { return v.Ident == "bundled_app" })
	if err := ipa.Set("/upload.ipa"); err != nil {
		t.Fatal(err)
	}
	if err := app.Set("com.example.Calc"); err != nil {
		t.Fatal(err)
	}
	if err := cfg.ValidateExcept(configurationExclusions(command.ModeActivateIPA)...); err != nil {
		t.Fatalf("IPA activation does not require a Driver or source build: %v", err)
	}
}

func TestDebugDefaultsOnlyChangeSelectedApplication(t *testing.T) {
	cfg := new(config.Model)
	if err := cfg.Init(new(command.Model)); err != nil {
		t.Fatal(err)
	}
	cfg.Debug = true
	set := func(ident, value string) *config.Var {
		t.Helper()
		variable, ok := cfg.Env.Get(func(v *config.Var) bool { return v.Ident == ident })
		if !ok {
			t.Fatalf("missing config variable %q", ident)
		}
		if err := variable.Set(value); err != nil {
			t.Fatal(err)
		}
		return variable
	}
	calcConfig := set("proj_config", "Release")
	calcBundle := set("bundled_app", "com.example.Calc.Release")
	driverSource := set("test_driver_source", "/driver")
	driverConfig := set("test_config", "Release")
	driverBundle := set("bundled_drv", "com.example.Driver.Release")

	applyDebugDefaults(cfg, command.ModeFull)
	if calcConfig.String() != "Debug" || calcBundle.String() != "com.example.Calc.App" {
		t.Fatalf("Calculator debug settings: config=%q bundle=%q", calcConfig.String(), calcBundle.String())
	}
	if driverSource.String() != "/driver" || driverConfig.String() != "Release" ||
		driverBundle.String() != "com.example.Driver.Release" {
		t.Fatalf("Calculator debug changed Driver selection: source=%q config=%q bundle=%q",
			driverSource.String(), driverConfig.String(), driverBundle.String())
	}

	calcConfig.UserDef = false
	calcBundle.UserDef = false
	driverConfig.UserDef = false
	driverBundle.UserDef = false
	if err := calcConfig.Set("Release"); err != nil {
		t.Fatal(err)
	}
	if err := calcBundle.Set("com.example.Calc.Release"); err != nil {
		t.Fatal(err)
	}
	applyDebugDefaults(cfg, command.ModeTestDriverOnly)
	if driverConfig.String() != "Debug" || driverBundle.String() != "com.example.Driver.App" {
		t.Fatalf("Driver debug settings: config=%q bundle=%q", driverConfig.String(), driverBundle.String())
	}
	if calcConfig.String() != "Release" || calcBundle.String() != "com.example.Calc.Release" {
		t.Fatalf("Driver debug changed Calculator selection: config=%q bundle=%q",
			calcConfig.String(), calcBundle.String())
	}
}

func TestParseFlagsSourceConfigurationBoundaries(t *testing.T) {
	for _, test := range []struct {
		name        string
		saved       string
		args        []string
		wantScratch bool
	}{
		{name: "unchanged", saved: "export proj_source='/calc'\nunset -v target_app_ipa\n"},
		{name: "stale IPA", saved: "export proj_source='/calc'\nexport target_app_ipa='/old.ipa'\n", wantScratch: true},
		{name: "bootstrap", args: []string{"--overwrite-config", "--target-app-source", "/calc"}},
	} {
		t.Run(test.name, func(t *testing.T) {
			dir := t.TempDir()
			path := filepath.Join(dir, "config.env")
			t.Setenv(config.SourceIdent, path)
			t.Setenv(config.BackupIdent, "")
			t.Setenv(config.TmpCfgIdent, t.TempDir())
			t.Setenv("proj_source", "")
			t.Setenv("target_app_ipa", "")
			if test.saved != "" {
				if err := os.WriteFile(path, []byte(test.saved), 0o600); err != nil {
					t.Fatal(err)
				}
			}
			oldArgs := os.Args
			os.Args = append([]string{"appium-agent"}, test.args...)
			t.Cleanup(func() { os.Args = oldArgs })
			cfg := &config.Model{EnvQuote: config.DefaultEnvQuote, Env: config.Env{
				config.NewVar("target-app-source", "p", "proj_source", config.String, ""),
				config.NewVar("target-app-ipa", "", "target_app_ipa", config.String, ""),
			}}
			scratch, err := parseFlags(cfg, new(command.Model))
			if err != nil {
				t.Fatal(err)
			}
			if (scratch != "") != test.wantScratch {
				t.Fatalf("scratch config=%q, want temporary=%t", scratch, test.wantScratch)
			}
			if test.wantScratch {
				path = scratch
			}
			saved, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			if strings.Contains(string(saved), "/old.ipa") || !strings.Contains(string(saved), "/calc") {
				t.Fatalf("source configuration retained a stale IPA or lost the source: %s", saved)
			}
		})
	}
}

func TestParseFlagsDeviceOperationsPreserveExplicitDevice(t *testing.T) {
	for _, operation := range []struct {
		flag string
		want string
	}{
		{"--reboot-device", "reboot --udid=explicitB"},
		{"--cycle-usb", "-s explicitB -a cycle"},
	} {
		t.Run(operation.flag, func(t *testing.T) {
			dir := t.TempDir()
			path := filepath.Join(dir, "config.env")
			explicit := filepath.Join(dir, "explicit.env")
			actions := filepath.Join(dir, "actions")
			for path, content := range map[string]string{
				path:     "export proj_source='/calc'\nexport target_app_ipa='/old.ipa'\nexport target_dest='id=defaultA'\n",
				explicit: "export target_dest='id=explicitB'\n",
			} {
				if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
					t.Fatal(err)
				}
			}
			script := `#!/bin/sh
if [ "$1" = listen ]; then
  printf '%s\n' '{"MessageType":"Attached","DeviceID":1,"Properties":{"SerialNumber":"defaultA"}}' '{"MessageType":"Attached","DeviceID":2,"Properties":{"SerialNumber":"explicitB"}}'
  exec /bin/sleep 30
fi
printf '%s\n' "$*" >"$ACTION_LOG"
exit 47
`
			for _, name := range []string{"ios", "uhubctl"} {
				if err := os.WriteFile(filepath.Join(dir, name), []byte(script), 0o700); err != nil {
					t.Fatal(err)
				}
			}
			t.Setenv("PATH", dir)
			t.Setenv("ACTION_LOG", actions)
			t.Setenv(config.SourceIdent, path)
			t.Setenv(command.AppiumdConfigIdent, explicit)
			oldArgs := os.Args
			os.Args = []string{"appium-agent", operation.flag}
			t.Cleanup(func() { os.Args = oldArgs })
			cfg := &config.Model{Env: config.Env{
				config.NewVar("target-app-source", "p", "proj_source", config.String, ""),
				config.NewVar("target-app-ipa", "", "target_app_ipa", config.String, ""),
				config.NewVar("target-device", "d", "target_dest", config.String, "id=defaultA"),
			}}
			if _, err := parseFlags(cfg, new(command.Model)); err == nil || !strings.Contains(err.Error(), "exit status 47") {
				t.Fatalf("hardware sentinel error=%v", err)
			}
			got, err := os.ReadFile(actions)
			if err != nil {
				t.Fatal(err)
			}
			if strings.TrimSpace(string(got)) != operation.want {
				t.Fatalf("hardware command=%q, want %q", got, operation.want)
			}
		})
	}
}
