package command

import "path/filepath"

const (
	AppiumdConfigIdent = "appium_config_env"
	RestartAppiumIdent = "appium_restart"
	LLDBManagedIdent   = "lldb_managed"
	AppiumModeIdent    = "appium_mode"
)

const (
	ModeFull               = "full"
	ModeRestart            = "restart"
	ModeTestDriverOnly     = "test-driver-only"
	ModeRelaunchTestDriver = "relaunch-test-driver"
	ModeActivateIPA        = "activate-ipa"
)

const (
	AppiumdTmuxSession = "Appium"
)

var AppiumdDefaultInit = func(root string) string { //nolint:gochecknoglobals
	return filepath.Join(root, "libexec", "appiumd.zsh")
}
