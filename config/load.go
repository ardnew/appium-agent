package config

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

// OverrideFile loads values from an appium-agent generated config.env file.
// Command-line values retain precedence, and the file is parsed without shell
// evaluation so inherited login-shell state cannot redirect partial modes.
func (e Env) OverrideFile(path string) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if ident, ok := strings.CutPrefix(line, "unset -v "); ok {
			ident = strings.TrimSpace(ident)
			variable, found := e.Get(func(v *Var) bool { return v.Ident == ident })
			if !found || variable.UserDef {
				continue
			}
			if err := variable.Set(""); err != nil {
				return fmt.Errorf("clear %s from %s: %w", ident, path, err)
			}
			continue
		}
		if !strings.HasPrefix(line, "export ") {
			continue
		}
		ident, value, ok := strings.Cut(strings.TrimPrefix(line, "export "), "=")
		if !ok {
			continue
		}
		variable, found := e.Get(func(v *Var) bool { return v.Ident == ident })
		if !found || variable.UserDef {
			continue
		}
		value = strings.TrimSpace(value)
		if len(value) >= 2 && value[0] == '\'' && value[len(value)-1] == '\'' {
			value = strings.ReplaceAll(value[1:len(value)-1], `'\''`, `'`)
		}
		if err := variable.Set(value); err != nil {
			return fmt.Errorf("load %s from %s: %w", ident, path, err)
		}
	}
	return scanner.Err()
}
