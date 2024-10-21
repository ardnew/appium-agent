package main

import (
	"bufio"
	"flag"
	"fmt"
	"io"
	"log"
	"maps"
	"os"
	"os/exec"
	"slices"
	"strings"

	"github.com/ardnew/appium-agent/command"
	"github.com/ardnew/appium-agent/config"
	"github.com/ardnew/appium-agent/status"
	"golang.org/x/sync/errgroup"
)

func main() {
	var (
		exe *exec.Cmd
		err error
	)
	defer func(e *error) {
		if *e != nil {
			log.Fatalf("error: %v", *e)
		}
	}(&err)

	cfg := new(config.Model)
	cmd := new(command.Model)

	if exe, err = initCommand(cmd); err == nil {
		if err = initConfig(cfg); err == nil {
			if err = parseFlags(cfg, cmd); err == nil {
				err = run(exe)
			}
		}
	}
}

func initConfig(cfg *config.Model) error {
	if err := cfg.Init(); err != nil {
		return fmt.Errorf("initialize Appium configuration: %w", err)
	}
	return nil
}

func initCommand(cmd *command.Model) (*exec.Cmd, error) {
	if err := cmd.Init(); err != nil {
		return nil, fmt.Errorf("initialize Appium launch command: %w", err)
	}
	sh, arg := cmd.Command()
	return exec.Command(sh, arg...), nil
}

func parseFlags(cfg *config.Model, cmd *command.Model) error {
	dryRun, overwrite := false, false
	flag.StringVar(&cmd.ScriptPath, "appium-init", cmd.ScriptPath, "`path` to Appium init script")
	flag.StringVar(&cmd.ShellPath, "appium-init-shell", cmd.ShellPath, "`path` of shell to run Appium init script")
	flag.StringVar(&cfg.Project, "target-app-source", cfg.Project, "`path` to Xcode project")
	flag.StringVar(&cfg.Target, "target-device", cfg.Target, "target device `UUID`")
	flag.BoolFunc("target-simulator", "use iPad Simulator target device", cfg.TargetSimulatorFlagHandler())
	flag.BoolVar(&cfg.Trace, "v", cfg.Trace, "verbose trace output")
	flag.StringVar(&cfg.Action, "xcodebuild-action", cfg.Action, "Xcode build `action`")
	// flag.StringVar(&cfg.server, "u", "", "Appium REST server URL")
	flag.StringVar(&cfg.AppID, "target-app-bundle", cfg.AppID, "`bundle` identifier of app under test")
	flag.StringVar(&cfg.DrvID, "test-driver-bundle", cfg.DrvID, "`bundle` identifier of test driver app")
	flag.StringVar(&cfg.DrvDev, "wda-network", cfg.DrvDev, "connect to WDA via network `interface`")
	flag.IntVar(&cfg.DrvPort, "wda-port", cfg.DrvPort, "connect to WDA on TCP `port`")
	flag.StringVar(&cfg.SrvDev, "listen-network", cfg.SrvDev, "bind Appium REST server to network `interface`")
	flag.IntVar(&cfg.SrvPort, "listen-port", cfg.SrvPort, "bind Appium REST server to TCP `port`")
	flag.BoolVar(&overwrite, "overwrite-config", false, "write Appium configuration to file")
	flag.BoolVar(&dryRun, "dryrun", false, "print configuration and launch command")
	flag.Parse()

	envFlags := maps.Values(cfg.Env)
	slices.SortedFunc(envFlags,
		func(a, b config.EnvVar) int {
			return strings.Compare(a.Flag, b.Flag)
		})
	sortedEnvFlags := slices.Collect(envFlags)

	flag.Visit(func(f *flag.Flag) {
		// If any configuration flag was set, we will overwrite the configuration file
		_, isConfigFlag := slices.BinarySearchFunc(
			sortedEnvFlags,
			config.EnvVar{Flag: f.Name},
			func(a, b config.EnvVar) int {
				return strings.Compare(a.Flag, b.Flag)
			})
		overwrite = overwrite || isConfigFlag
	})

	if err := cfg.Update(); err != nil {
		return fmt.Errorf("validate Appium configuration: %w", err)
	}

	if dryRun {
		// Print configuration and launch command to stdout, then exit.
		if err := writeConfig(os.Stdout, cfg, cmd); err != nil {
			return fmt.Errorf("generate Appium configuration: %w", err)
		}
		os.Exit(0)
	}

	if overwrite {
		// Backup and write config to file (tee to stdout if -v flag is set).
		if err := install(cfg, cmd, cfg.Trace, os.Stdout); err != nil {
			return fmt.Errorf("install Appium configuration: %w", err)
		}
	}

	return nil
}

func install(cfg *config.Model, cmd *command.Model, tee bool, wTee ...io.Writer) error {
	env, err := config.LookupSource()
	if err != nil {
		return fmt.Errorf("find Appium configuration: %w", err)
	}
	if bak, lerr := config.LookupBackup(env); lerr == nil {
		if berr := config.Backup(env, bak); berr != nil {
			return fmt.Errorf("backup Appium configuration: %w", berr)
		}
	}
	out, err := os.OpenFile(env, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644) //nolint:gomnd,mnd
	if err != nil {
		return fmt.Errorf("%w: %q: %w", status.ErrOpenFile, env, err)
	}
	defer out.Close()
	var wAll io.Writer = out
	if tee && len(wTee) > 0 {
		a := make([]io.Writer, 0, len(wTee)+1)
		a = append(a, out)
		a = append(a, wTee...)
		wAll = io.MultiWriter(a...)
	}
	return writeConfig(wAll, cfg, cmd)
}

func writeConfig(out io.Writer, cfg *config.Model, cmd *command.Model) error {
	abs, err := os.Executable()
	if err != nil {
		return fmt.Errorf("absolute path of executable: %w", err)
	}
	sh, args := cmd.Command()
	if err = cfg.Write(
		out,
		fmt.Sprintf("# Use command to start Appium:\n#   %s\n", abs),
		fmt.Sprintf("#\n# (invokes: %q)\n\n", append([]string{sh}, args...)),
	); err != nil {
		return fmt.Errorf("write Appium configuration: %w", err)
	}
	return nil
}

func run(exe *exec.Cmd) error {
	stdout, _ := exe.StdoutPipe()
	stderr, _ := exe.StderrPipe()
	scanout := bufio.NewReader(stdout)
	scanerr := bufio.NewReader(stderr)

	copyFunc := func(w io.Writer, r io.Reader) func() error {
		return func() error {
			if _, cerr := io.Copy(w, r); cerr != nil {
				return fmt.Errorf("copy stdio: %w", cerr)
			}
			return nil
		}
	}

	grp := new(errgroup.Group)
	grp.Go(copyFunc(os.Stderr, scanerr))
	grp.Go(copyFunc(os.Stdout, scanout))

	if err := exe.Run(); err != nil {
		return fmt.Errorf("exec.Command: %w", err)
	}
	if err := grp.Wait(); err != nil {
		return fmt.Errorf("copy output from exec.Command: %w", err)
	}

	return nil
}
