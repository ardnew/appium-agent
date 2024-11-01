package command

import (
	"flag"
	"fmt"
	"os"

	"github.com/ardnew/appium-agent/status"
)

type Model struct {
	ShellPath    string
	ShellArgs    []string
	ScriptPath   string
	ForceRestart bool
	SkipBuild    bool
}

func (m *Model) Init() error {
	if m.ShellPath == "" {
		// Initialize output so that the env var ident is printed in error messages
		// when lookup fails. This informs the user how to correct the issue.
		m.ShellPath = "SHELL"
		if p, ok := os.LookupEnv(m.ShellPath); ok {
			m.ShellPath = p
		}
	}
	if m.ScriptPath == "" {
		// See comment above `c.shellPath = "SHELL"` for reason of the following.
		m.ScriptPath = "FSDS_PREFIX"
		if root, ok := os.LookupEnv(m.ScriptPath); ok {
			m.ScriptPath = AppiumdDefaultInit(root)
		}
	}
	if m.ShellPath == "SHELL" { // SHELL variable not found in env
		var err error
		m.ShellPath, m.ShellArgs, err = ParseShebangFrom(m.ScriptPath)
		if err != nil {
			return err
		}
	}
	if _, err := os.Stat(m.ScriptPath); err != nil {
		return fmt.Errorf("%w: %s: %w", status.ErrInvalidScript, m.ScriptPath, err)
	}
	if _, err := os.Stat(m.ShellPath); err != nil {
		return fmt.Errorf("%w: %s: %w", status.ErrInvalidShell, m.ShellPath, err)
	}
	return nil
}

func (m Model) Command() (string, []string) {
	arg := m.ShellArgs
	arg = append(arg, DefaultShellFlags()...)
	arg = append(arg, m.ScriptPath)
	arg = append(arg, flag.Args()...)
	return m.ShellPath, arg
}
