package command

import "path/filepath"

const (
	AppiumdConfigIdent = "appium_config_env"
	RestartAppiumIdent = "appium_restart"
	LLDBManagedIdent   = "lldb_managed"
)

const (
	AppiumdTmuxSession = "Appium"
)

var AppiumdDefaultInit = func(root string) string { //nolint:gochecknoglobals
	return filepath.Join(root, "libexec", "appiumd.zsh")
}
