package config

import (
	"fmt"
	"io"
	"os"
	"slices"
	"strconv"
	"strings"
	"time"

	flag "github.com/spf13/pflag"

	"github.com/ardnew/appium-agent/status"
)

type Model struct {
	Env      Env
	EnvQuote rune
	Orphan   bool
	Zero     bool
}

func (m *Model) Init() error {
	m.Env = DefaultEnv().Sort(orderByFlag)
	m.EnvQuote = DefaultEnvQuote
	return nil
}

func (m *Model) ApplyToFlags(visit func(func(f *flag.Flag)), apply func(*Var) bool) bool {
	result := false
	visit(
		func(f *flag.Flag) {
			i, found := slices.BinarySearchFunc(
				m.Env, &Var{Flag: f.Name}, orderByFlag,
			)
			if found {
				result = apply(m.Env[i]) || result
			}
		})
	return result
}

func (m *Model) Validate() error {
	for _, val := range m.Env {
		if strings.TrimSpace(val.String()) == "" {
			return fmt.Errorf("%w: %q", status.ErrIdentUndef, val.Ident)
		}
	}
	return nil
}

func (m *Model) TargetSimulatorFlagHandler() func(string) error {
	return func(s string) error {
		if s != "" {
			truth, err := strconv.ParseBool(s)
			if err != nil {
				return fmt.Errorf("invalid argument (bool expected): %q: %w", s, err)
			}
			if !truth {
				return nil
			}
		}
		if target, ok := m.Env.Get(func(v *Var) bool {
			return v.Ident == "target_dest" || v.Flag == "target-device"
		}); ok {
			_ = target.Set(DefaultiPadSim)
		}
		return nil
	}
}

func (m *Model) Write(out io.Writer, footer ...string) error {
	fmt.Fprintln(out, "# ==============================================================================")
	fmt.Fprintln(out, "#  FSDS Appium Configuration -- DO NOT EDIT")
	fmt.Fprintln(out, "# ------------------------------------------------------------------------------")
	fmt.Fprintf(out, "#  Generated on %s with:\n#    %q\n", time.Now().Format(time.RFC1123), os.Args)
	fmt.Fprintln(out, "# ==============================================================================")
	fmt.Fprintln(out)
	fmt.Fprintln(out, m) // <- All of the export statements
	for _, line := range footer {
		fmt.Fprint(out, line)
	}
	return nil
}

func (m *Model) String() string {
	var str strings.Builder
	for i, val := range m.Env {
		if i > 0 {
			str.WriteRune('\n')
		}
		for _, c := range val.Comment {
			str.WriteString("# ")
			str.WriteString(c)
			str.WriteRune('\n')
		}
		if !val.UserDef && val.String() == "" {
			str.WriteString("unset -v ")
			str.WriteString(val.Ident)
		} else {
			str.WriteString("export ")
			str.WriteString(val.Ident)
			str.WriteRune('=')
			fullVal := val.String()
			trimVal := strings.TrimSpace(fullVal)
			switch val.VType {
			case Int, Float:
				str.WriteString(trimVal) // Don't quote numbers
			case Bool, String, JSON, Serial:
				if strings.HasPrefix(trimVal, "$(") && strings.HasSuffix(trimVal, ")") {
					str.WriteString(trimVal) // Don't quote command substitution
				} else {
					str.WriteRune(m.EnvQuote) // Quote everything else,
					str.WriteString(fullVal)  //  and retain untrimmed values.
					str.WriteRune(m.EnvQuote)
				}
			}
		}
		str.WriteRune('\n')
	}
	return str.String()
}
