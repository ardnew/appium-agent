package config

import (
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/ardnew/appium-agent/status"
)

type Model struct {
	Env      map[string]EnvVar
	EnvQuote rune

	Project string
	Target  string
	Action  string
	Trace   bool
	// server   string
	AppID   string
	DrvID   string
	DrvDev  string
	DrvPort int
	SrvDev  string
	SrvPort int
}

type EnvVar struct {
	Value   string
	Comment string
	Flag    string
}

func (m *Model) Init() error {
	// Initialize the environment values with default values.
	// This also considers the caller's environment,
	// which takes precedence over the default values.
	m.Env = DefaultEnv()
	// Initialize the local variables with the environment values.
	// This also defines the default values of command-line flags.
	m.Project = m.Env["project_src"].Value
	m.Target = m.Env["target_dest"].Value
	m.Action = m.Env["xcbuild_act"].Value
	m.Trace, _ = strconv.ParseBool(m.Env["trace_agent"].Value)
	m.AppID = m.Env["bundled_app"].Value
	m.DrvID = m.Env["bundled_drv"].Value
	m.DrvDev = m.Env["driver_name"].Value
	m.DrvPort, _ = strconv.Atoi(m.Env["driver_port"].Value)
	m.SrvDev = m.Env["listen_name"].Value
	m.SrvPort, _ = strconv.Atoi(m.Env["listen_port"].Value)
	// All other initialization
	m.EnvQuote = DefaultEnvQuote
	return nil
}

func (m *Model) Update() error {
	// Update the environment values with the local variables.
	//
	// This should be done after local variables are set via command-line flags.
	//
	// If a command-line flag didn't set a local variable, then its value will
	// be retained from initialization (either default or caller's environment).
	update := func(ident string, val string) {
		if v, ok := m.Env[ident]; ok {
			v.Value = val
			v.Comment = ""
			m.Env[ident] = v
		}
	}
	update("project_src", m.Project)
	update("target_dest", m.Target)
	update("xcbuild_act", m.Action)
	update("trace_agent", strconv.FormatBool(m.Trace))
	update("bundled_app", m.AppID)
	update("bundled_drv", m.DrvID)
	update("driver_name", m.DrvDev)
	update("driver_port", strconv.Itoa(m.DrvPort))
	update("listen_name", m.SrvDev)
	update("listen_port", strconv.Itoa(m.SrvPort))

	return m.Validate()
}

func (m *Model) Validate() error {
	for ident, val := range m.Env {
		if strings.TrimSpace(val.Value) == "" {
			return fmt.Errorf("%w: %q", status.ErrIdentUndef, ident)
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
		m.Target = DefaultiPadSim
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
		fmt.Fprintln(out, line)
	}
	return nil
}

func (m *Model) String() string {
	var str strings.Builder
	for _, ident := range Vars(m.Env) {
		val := m.Env[ident]
		if val.Comment != "" {
			str.WriteString("# ")
			str.WriteString(val.Comment)
			str.WriteRune('\n')
		}
		str.WriteString("export ")
		str.WriteString(ident)
		str.WriteRune('=')
		trimVal := strings.TrimSpace(val.Value)
		intVal, intErr := strconv.ParseInt(trimVal, 0, 64)
		switch {
		case intErr == nil:
			str.WriteString(strconv.FormatInt(intVal, 10)) // Don't quote integers
		case strings.HasPrefix(trimVal, "$(") && strings.HasSuffix(trimVal, ")"):
			str.WriteString(trimVal) // Don't quote command substitution
		default:
			str.WriteRune(m.EnvQuote)
			str.WriteString(val.Value)
			str.WriteRune(m.EnvQuote)
		}
		str.WriteRune('\n')
	}
	return str.String()
}
