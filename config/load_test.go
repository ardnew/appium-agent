package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestOverrideFileDriverSelectionPreservesSavedCalcState(t *testing.T) {
	for _, setting := range []struct {
		ident string
		value string
	}{
		{"bundled_app", "com.stale.Calc"},
		{"proj_config", "Debug"},
		{"proj_source", "/stale/calc.xcodeproj"},
		{"proj_scheme", "Stale Calc Scheme"},
		{"target_app_ipa", "/stale/upload.ipa"},
		{"test_driver_source", "/stale/driver.xcodeproj"},
		{"test_driver_scheme", "Stale Driver Scheme"},
		{"test_config", "Stale"},
	} {
		t.Setenv(setting.ident, setting.value)
	}
	env := DefaultEnv().Override(false, false)
	value := func(ident string) *Var {
		t.Helper()
		variable, ok := env.Get(func(v *Var) bool { return v.Ident == ident })
		if !ok {
			t.Fatalf("missing config variable %q", ident)
		}
		return variable
	}
	driverSource, driverScheme, driverConfig := value("test_driver_source"), value("test_driver_scheme"), value("test_config")
	for _, setting := range []struct {
		variable *Var
		value    string
	}{
		{driverSource, "/selected/driver.xcodeproj"},
		{driverScheme, "Selected Driver Scheme"},
		{driverConfig, "Debug"},
	} {
		if err := setting.variable.Set(setting.value); err != nil {
			t.Fatal(err)
		}
		setting.variable.UserDef = true
	}

	path := filepath.Join(t.TempDir(), "config.env")
	data := `export bundled_app='com.saved.Calc'
export proj_config='Release'
export proj_scheme='Saved Calc Scheme'
export proj_source='/saved/calc.xcodeproj'
export target_app_ipa='/saved/upload.ipa'
export test_driver_source='/saved/driver.xcodeproj'
export test_driver_scheme='Saved Driver Scheme'
export test_config='Release'
export bundled_drv='com.saved.Driver'
`
	if err := os.WriteFile(path, []byte(data), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := env.OverrideFile(path); err != nil {
		t.Fatal(err)
	}
	for _, want := range []struct {
		variable *Var
		value    string
	}{
		{value("bundled_app"), "com.saved.Calc"},
		{value("proj_config"), "Release"},
		{value("proj_source"), "/saved/calc.xcodeproj"},
		{value("proj_scheme"), "Saved Calc Scheme"},
		{value("target_app_ipa"), "/saved/upload.ipa"},
		{driverSource, "/selected/driver.xcodeproj"},
		{driverScheme, "Selected Driver Scheme"},
		{driverConfig, "Debug"},
		{value("bundled_drv"), "com.saved.Driver"},
	} {
		if got := want.variable.String(); got != want.value {
			t.Errorf("%s=%q, want %q", want.variable.Ident, got, want.value)
		}
	}
}

func TestOverrideFileCalcSelectionPreservesSavedDriverState(t *testing.T) {
	for _, setting := range []struct {
		ident string
		value string
	}{
		{"bundled_app", "com.stale.Calc"},
		{"proj_config", "Stale"},
		{"proj_source", "/stale/calc.xcodeproj"},
		{"proj_scheme", "Stale Calc Scheme"},
		{"target_app_ipa", "/stale/upload.ipa"},
		{"test_driver_source", "/stale/driver.xcodeproj"},
		{"test_driver_scheme", "Stale Driver Scheme"},
		{"test_config", "Stale"},
		{"bundled_drv", "com.stale.Driver"},
	} {
		t.Setenv(setting.ident, setting.value)
	}
	env := DefaultEnv().Override(false, false)
	value := func(ident string) *Var {
		t.Helper()
		variable, ok := env.Get(func(v *Var) bool { return v.Ident == ident })
		if !ok {
			t.Fatalf("missing config variable %q", ident)
		}
		return variable
	}
	for _, setting := range []struct {
		variable *Var
		value    string
	}{
		{value("bundled_app"), "com.cli.Calc"},
		{value("proj_config"), "Release"},
		{value("proj_source"), "/cli/calc.xcodeproj"},
		{value("target_app_ipa"), "/cli/upload.ipa"},
		{value("proj_scheme"), "CLI Calc Scheme"},
	} {
		if err := setting.variable.Set(setting.value); err != nil {
			t.Fatal(err)
		}
		setting.variable.UserDef = true
	}
	path := filepath.Join(t.TempDir(), "config.env")
	data := `export bundled_app='com.saved.Calc'
export proj_config='Debug'
export proj_source='/saved/calc.xcodeproj'
export target_app_ipa='/saved/upload.ipa'
export proj_scheme='Saved Calc Scheme'
export test_driver_source='/saved/driver.xcodeproj'
export test_driver_scheme='Saved Driver Scheme'
export test_config='Release'
export bundled_drv='com.saved.Driver'
`
	if err := os.WriteFile(path, []byte(data), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := env.OverrideFile(path); err != nil {
		t.Fatal(err)
	}
	for _, want := range []struct {
		variable *Var
		value    string
	}{
		{value("bundled_app"), "com.cli.Calc"},
		{value("proj_config"), "Release"},
		{value("proj_source"), "/cli/calc.xcodeproj"},
		{value("proj_scheme"), "CLI Calc Scheme"},
		{value("target_app_ipa"), "/cli/upload.ipa"},
		{value("test_driver_source"), "/saved/driver.xcodeproj"},
		{value("test_driver_scheme"), "Saved Driver Scheme"},
		{value("test_config"), "Release"},
		{value("bundled_drv"), "com.saved.Driver"},
	} {
		if got := want.variable.String(); got != want.value {
			t.Errorf("%s=%q, want %q", want.variable.Ident, got, want.value)
		}
	}
}
