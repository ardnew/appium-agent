package config

// Standalone functions (non-methods) supporting type Model.

import (
	"encoding"
	"encoding/json"
	"errors"
	"fmt"
	"iter"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/ardnew/appium-agent/status"
	"github.com/muesli/reflow/wordwrap"
)

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

func LookupTempConfig(base, name string) (string, error) {
	path, ok := os.LookupEnv(TmpCfgIdent)
	if path == "" || !ok {
		out, err := exec.Command("getconf", "DARWIN_USER_CACHE_DIR").CombinedOutput()
		if err != nil {
			path, err = os.MkdirTemp("", base)
			if err != nil {
				return "", fmt.Errorf("%w: no suitable temporary directory", status.ErrInvalidConfig)
			}
		} else {
			path = filepath.Join(strings.TrimSpace(string(out)), base)
		}
	}
	info, err := os.Stat(path)
	if err == nil {
		if info.IsDir() {
			path = filepath.Join(path, name)
		}
		return path, nil
	}
	if errors.Is(err, os.ErrNotExist) {
		if err := os.MkdirAll(path, 0o755); err != nil { //nolint:gomnd,mnd
			return "", fmt.Errorf("%w: %q: %w", status.ErrInvalidConfig, path, err)
		}
		return filepath.Join(path, name), nil
	}
	return "", fmt.Errorf("%w: invalid path: %q", status.ErrInvalidConfig, path)
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

func Filter[T any](seq iter.Seq[T], keep func(T) bool) []T {
	var defined []T
	for v := range seq {
		if keep(v) {
			defined = append(defined, v)
		}
	}
	return defined
}

func encode[T any](v *Var, fn func(T) string) (s string) {
	sel := v.EnvValue
	if v.UserDef || !v.Zero {
		sel = v.Value
	}
	if !v.Aggr {
		av, ok := sel.(T)
		if !ok {
			return
		}
		return fn(av)
	}
	if l, ok := sel.([]T); ok {
		for i, n := range l {
			if i > 0 {
				s += ","
			}
			s += fn(n)
		}
	}
	return
}

func decode[T any](v *Var, s string, fn func(string) (T, error)) error {
	// Always record both the given value (r) and the envionment value (e).
	//
	// Which one is used (via Var.String()) depends on the UserDef flag
	// (which is set iff the corresponding command-line flag was provided).
	var r, e T
	if !v.Zero {
		r, _ = fn(s)
	}
	if !v.Orphan {
		if env, ok := os.LookupEnv(v.Ident); ok {
			if ev, err := fn(env); err == nil {
				e = ev
			}
		}
	}
	if !v.Aggr {
		v.Value = r
		v.EnvValue = e
	} else if l, ok := v.Value.([]T); ok {
		v.Value = append(l, r) //nolint:gocritic
		v.EnvValue = append(l, e)
	} else {
		v.Value = []T{r}
		v.EnvValue = []T{e}
	}
	return nil
}

func encodeFloat(f float64) string {
	return strconv.FormatFloat(f, 'f', -1, 64)
}

func encodeJSON(j any) string {
	if b, err := json.Marshal(j); err == nil {
		return string(b)
	}
	return ""
}

func encodeSerial(s encoding.TextMarshaler) string {
	if b, err := s.MarshalText(); err == nil {
		return string(b)
	}
	return ""
}

func decodeFloat(s string) (float64, error) {
	return strconv.ParseFloat(s, 64)
}

func decodeJSON(v *Var) func(string) (any, error) {
	return func(s string) (any, error) {
		if err := json.Unmarshal([]byte(s), &v.Value); err != nil {
			return nil, err
		}
		return v.Value, nil
	}
}

func decodeSerial(v *Var) func(string) (encoding.TextUnmarshaler, error) {
	return func(s string) (encoding.TextUnmarshaler, error) {
		dec, ok := v.Value.(encoding.TextUnmarshaler)
		if !ok {
			return nil,
				fmt.Errorf("%w: invalid %T value", errors.ErrUnsupported, v.Value)
		}
		return dec, dec.UnmarshalText([]byte(s))
	}
}

func wrap(n uint, b []byte) []byte {
	if uint(len(b)) <= n {
		return b
	}
	ww := wordwrap.NewWriter(int(n)) //nolint:gosec
	ww.Breakpoints = []rune("\t\r\n /")
	_, _ = ww.Write(b)
	_ = ww.Close()
	return ww.Bytes()
}
