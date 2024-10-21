package config

// Standalone functions (non-methods) supporting type Model.

import (
	"errors"
	"fmt"
	"maps"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/ardnew/appium-agent/status"
)

func MakeEnvVar(value, flag string, comment ...string) EnvVar {
	return EnvVar{Value: value, Flag: flag, Comment: strings.Join(comment, " ")}
}

func DefaultEnv() map[string]EnvVar {
	env := map[string]EnvVar{
		"sdk_version": MakeEnvVar(
			"$( xcrun --sdk iphoneos --show-sdk-version )", "",
			"Use whatever iOS SDK we have activated system-wide [see: xcode-select(1)]",
		),
		"project_src": MakeEnvVar("", "target-app-source"),
		"bundled_app": MakeEnvVar("com.NorthropGrumman.FMPS-Calculator.Test", "target-app-bundle"),
		"bundled_drv": MakeEnvVar("com.NorthropGrumman.FMPS-Test-Driver", "test-driver-bundle"),
		"target_dest": MakeEnvVar("id=00008101-0005499E010B001E", "target-device"),
		"driver_name": MakeEnvVar("en0", "wda-network"),
		"driver_port": MakeEnvVar("8100", "wda-port"),
		"listen_name": MakeEnvVar("en5", "listen-network"),
		"listen_port": MakeEnvVar("4723", "listen-port"),
		"xcbuild_act": MakeEnvVar("test", "xcodebuild-action"),
		"trace_agent": MakeEnvVar("false", "v"),
	}
	// Overwrite any default value with values from the caller's environment.
	for ident, def := range env {
		if val, ok := os.LookupEnv(ident); ok {
			env[ident] = EnvVar{Value: val, Flag: def.Flag}
		}
	}
	return env
}

func BoolString(b bool) string {
	if b {
		return "true"
	}
	return "false"
}

func Vars(env map[string]EnvVar) []string {
	return slices.Sorted(maps.Keys(env))
}

func LookupSource() (string, error) {
	path, ok := os.LookupEnv(SourceIdent)
	if !ok || path == "" {
		return "", fmt.Errorf("%w: %s=%q", status.ErrInvalidConfig, SourceIdent, path)
	}
	info, err := os.Stat(path)
	// The source env var value is interpreted as a regular file path.
	// Make the source path's parent directories if it doesn't exist.
	if errors.Is(err, os.ErrNotExist) {
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil { //nolint:gomnd,mnd
			return "", fmt.Errorf("%w: %q: %w", status.ErrInvalidConfig, path, err)
		}
	} else if info.IsDir() {
		// Ignore the source path if it's a directory (cannot assume file name).
		return "", fmt.Errorf("%w: file exists as a directory: %q", status.ErrInvalidConfig, path)
	}
	return path, nil
}

func LookupBackup(source string) (string, error) {
	if source == "" {
		return "", fmt.Errorf(
			"%w: no source path defined for backup: %s", os.ErrNotExist, SourceIdent,
		)
	}
	path, ok := os.LookupEnv(BackupIdent)
	if path == "" || !ok {
		return "", fmt.Errorf("%w: %s=%q", os.ErrNotExist, BackupIdent, path)
	}
	info, err := os.Stat(path)
	if errors.Is(err, os.ErrNotExist) || info.IsDir() {
		if err := os.MkdirAll(path, 0o755); err != nil { //nolint:gomnd,mnd
			return "", fmt.Errorf("%w: %s=%q", status.ErrInvalidBackup, BackupIdent, path)
		}
		return filepath.Join(path, filepath.Base(source)), nil
	}
	return path, nil
}

func Backup(source, backup string) error {
	// Don't attempt to backup or return an error
	// if only one path (or neither) is provided.
	if source != "" && backup != "" {
		if err := os.Rename(source, backup); err != nil {
			return fmt.Errorf(
				"%w: backup: %q -> %q: %w", status.ErrWriteFile, source, backup, err,
			)
		}
	}
	return nil
}
