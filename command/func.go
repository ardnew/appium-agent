package command

// Standalone functions (non-methods) supporting type Model.

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/ardnew/appium-agent/status"
)

func DefaultShellFlags() []string {
	return []string{"-i", "-l"} // Interactive login shell
}

func Split(s string, quote []rune, delim []rune) []string {
	const none = '\000'
	open := none
	return strings.FieldsFunc(s, func(curr rune) bool {
		switch {
		case open == none:
			if strings.ContainsRune(string(quote), curr) {
				open = curr
				return false
			}
			return strings.ContainsRune(string(delim), curr)
		case open == curr:
			open = none
		}
		return false
	})
}

func ReadShebang(r io.Reader) (string, error) {
	b := bufio.NewReader(r)
	top, _, err := b.ReadLine()
	if err != nil {
		return "", fmt.Errorf("%w: %w", status.ErrReadFile, err)
	}
	return string(top), nil
}

func ReadShebangFrom(path string) (string, error) {
	scp, err := os.Open(path)
	if err != nil {
		return "", fmt.Errorf("%w: %q: %w", status.ErrOpenFile, path, err)
	}
	defer scp.Close()
	return ReadShebang(bufio.NewReader(scp))
}

func ParseShebangEnvArgs(args ...string) (string, []string, error) {
	// If the shebang uses the env command as interpreter, discard it
	// and all of its flags (anything with a "-" prefix), and return
	// what follows as command and arguments.
	flagSplit := false
	for idx, arg := range args {
		// The loop will return early at the first non-flag argument.
		if strings.HasPrefix(arg, "-") {
			flagSplit = flagSplit || strings.HasPrefix(arg, "-S")
			continue
		}
		// Mimic the behavior of env -S, which splits the command
		// and arguments properly as separate elements of argv[].
		if flagSplit {
			return arg, args[idx+1:], nil
		}
		// Otherwise, all non-flag arguments given to env are
		// combined as a single-string command to execute.
		return strings.Join(args[idx:], " "), nil, nil
	}
	// We should never exit the loop unless there are no non-flag
	// arguments to env, which is an invalid shebang.
	return "", nil, status.ErrParseShebang
}

func ParseShebang(line string) (string, []string, error) {
	if len(line) < 2 || line[0] != '#' || line[1] != '!' {
		return "", nil, status.ErrParseShebang
	}
	argv := Split(line[2:], []rune(`'"`), []rune(" \t"))
	switch len(argv) {
	case 0:
		return "", nil, status.ErrParseShebang
	case 1:
		return argv[0], nil, nil
	default:
		if filepath.Base(argv[0]) == "env" {
			return ParseShebangEnvArgs(argv[1:]...)
		}
		return argv[0], argv[1:], nil
	}
}

func ParseShebangFrom(path string) (string, []string, error) {
	line, err := ReadShebangFrom(path)
	if err != nil {
		return "", nil, err
	}
	return ParseShebang(line)
}
