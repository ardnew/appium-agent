package main

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	flag "github.com/spf13/pflag"
	"golang.org/x/sync/errgroup"

	"github.com/ardnew/appium-agent/command"
	"github.com/ardnew/appium-agent/config"
	"github.com/ardnew/appium-agent/status"
)

var Version = "0.3.1"

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
		if err = initConfig(cfg, cmd); err == nil {
			var tmpConfig string
			if tmpConfig, err = parseFlags(cfg, cmd); err == nil {
				exe.Env = exe.Environ()
				if tmpConfig != "" {
					export := fmt.Sprintf("%s=%s", command.AppiumdConfigIdent, tmpConfig)
					fmt.Printf("NOTE: using temporary Appium configuration:\n\t%s\n", export)
					exe.Env = append(exe.Env, export)
				}
				if cmd.SkipBuild {
					exe.Env = append(exe.Env, fmt.Sprintf("%s=%s", command.RestartAppiumIdent, "true"))
				}
				if cmd.ForceRestart {
					if err = command.KillAll(exe); err != nil {
						err = fmt.Errorf("kill all Appium services: %w", err)
					}
				}
				err = run(exe)
			}
		}
	}
}

func initConfig(cfg *config.Model, cmd *command.Model) error {
	if err := cfg.Init(cmd); err != nil {
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

func parseFlags(cfg *config.Model, cmd *command.Model) (string, error) {
	bin, err := os.Executable()
	if err != nil {
		bin = os.Args[0]
	}
	bin = filepath.Base(bin)

	fset, verbose, dryRun, overwrite := makeFlagSet(bin, cfg, cmd)
	if err = fset.Parse(os.Args[1:]); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			os.Exit(0)
		}
		return "", fmt.Errorf("parse command line flags: %w", err)
	}

	// Determine if we are running with modified configuration.
	//
	// First, the flags were all initialized
	// with default, hard-coded values
	// in makeFlagSet() above.
	//
	// Next, we identify which values were given via command-line flags
	// and mark them as user-defined.
	// This is important because we need to know which variables to override
	// with values inherited from the environment below
	//  (user-defined command-line flags take precedence).

	// Here, we override all configuration parameters
	// that were defined via command-line flags
	//  (and mark them accordingly with .UserDef = true).
	modifyConfig := cfg.ApplyToFlags(fset.Visit, // only those that were set
		func(v *config.Var) bool { v.UserDef = true; return true },
	)

	// Any operation that modifies flags based on a given command-line flag
	// MUST set the UserDef flag to true on the given flag
	// AND all collateral flags that were modified.
	type modVar func(*config.Var)

	modDefault := func(flag string, mod modVar) {
		ptr, found := cfg.Env.Get(func(v *config.Var) bool {
			return v.Flag == flag || v.PFlag == flag
		})
		if found && !ptr.UserDef {
			mod(ptr)
			ptr.UserDef = true // mark as user-defined
		}
	}
	reset := func(str string) modVar {
		return func(env *config.Var) {
			env.Set(str)
		}
	}
	setTail := func(str string) modVar {
		return func(env *config.Var) {
			id := strings.Split(env.String(), ".")
			if len(id) > 0 {
				id[len(id)-1] = str
			}
			env.Set(strings.Join(id, "."))
		}
	}

	if cfg.Debug {
		modDefault("target-app-config", reset("Debug"))
		modDefault("test-driver-config", reset("Debug"))
		modDefault("target-app-bundle", setTail("Debug"))
		modDefault("test-driver-bundle", setTail("Debug"))
	}

	// We now need to override any configuration parameters
	// found in the environment that were not already set via command-line flags.
	cfg.Env = cfg.Env.Override(cfg.Orphan, cfg.Zero)

	if *dryRun {
		// Print configuration and launch command to stdout, then exit.
		if err = writeConfig(os.Stdout, cfg, cmd); err != nil {
			return "", fmt.Errorf("generate Appium configuration: %w", err)
		}
		os.Exit(0)
	}

	if err = cfg.Validate(); err != nil {
		return "", fmt.Errorf("validate Appium configuration: %w", err)
	}

	var tmpConfig string
	if modifyConfig {
		if *overwrite {
			// Backup and write config to default file path
			//  (tee to stdout if --verbose flag is set).
			if err = install(cfg, cmd, *verbose, os.Stdout); err != nil {
				return "", fmt.Errorf("install Appium configuration: %w", err)
			}
		} else {
			// Write config to a temporary file without backup
			//  (tee to stdout if --verbose flag is set).
			if tmpConfig, err = scratch(cfg, cmd, bin, *verbose, os.Stdout); err != nil {
				return "", fmt.Errorf("install Appium configuration (temp): %w", err)
			}
		}
	}

	// tmpConfig is defined only if the user has overridden a config parameter
	// but is NOT saving the configuration to the default config file.
	// This allows for one-off test runs without committing anything to disk.
	return tmpConfig, nil
}

func makeFlagSet(
	bin string, cfg *config.Model, cmd *command.Model,
) (fset *flag.FlagSet, verbose, dryRun, overwrite *bool) {
	fset = flag.NewFlagSet(bin, flag.ContinueOnError)
	verbose = new(bool)
	dryRun = new(bool)
	overwrite = new(bool)
	fset.StringVarP(&cmd.ScriptPath, "appium-init", "i", cmd.ScriptPath,
		"`path` to Appium init script")
	fset.StringVarP(&cmd.ShellPath, "appium-init-shell", "e", cmd.ShellPath,
		"`path` of shell to run Appium init script")
	fset.BoolVarP(&cmd.ForceRestart, "kill-with-fire", "f", cmd.ForceRestart,
		"Kill all running Appium services before starting")
	fset.BoolVarP(&cmd.SkipBuild, "restart-appium", "r", cmd.SkipBuild,
		"Restart Appium without building the target app or test driver")
	fset.BoolVarP(&cfg.Debug, "debug-config", "g", false,
		"Use the target debug configuration by default")
	fset.BoolVarP(overwrite, "overwrite-config", "w", false,
		"Write Appium configuration to file")
	fset.BoolVarP(dryRun, "dryrun", "y", false,
		"Print configuration and launch command")
	fset.BoolVarP(&cfg.Orphan, "orphan", "j", false,
		"Do not inherit configuration parameters from current environment\n"+
			"(combine with -z to use command-line flags only)")
	fset.BoolVarP(&cfg.Zero, "zero", "z", false,
		"Do not initialize default configuration parameters\n"+
			"(use command-line flags or environment variables only)")
	fset.BoolVarP(verbose, "verbose", "v", false,
		"Increase output verbosity")
	opVar := []*config.Var{}
	fset.VisitAll(func(f *flag.Flag) {
		typ := config.ParseType(f.Value.Type())
		val := f.Value.String()
		opVar = append(opVar, config.NewVar(f.Name, f.Shorthand, "", typ, val, f.Usage))
	})
	for i := range cfg.Env {
		f := fset.VarPF(
			cfg.Env[i],
			cfg.Env[i].Flag,
			cfg.Env[i].PFlag,
			strings.Join(cfg.Env[i].Comment, " "),
		)
		if cfg.Env[i].IsBoolFlag() {
			f.NoOptDefVal = "true"
		}
	}
	fset.Usage = cfg.Env.Usage(bin, Version, opVar...)
	return
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

func scratch(cfg *config.Model, cmd *command.Model, base string, tee bool, wTee ...io.Writer) (string, error) {
	path, err := config.LookupTempConfig(base, "config.env")
	if err != nil {
		return "", fmt.Errorf("resolve temporary Appium configuration: %w", err)
	}
	out, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644) //nolint:gomnd,mnd
	if err != nil {
		return "", fmt.Errorf("%w: %q: %w", status.ErrOpenFile, path, err)
	}
	defer out.Close()
	var wAll io.Writer = out
	if tee && len(wTee) > 0 {
		a := make([]io.Writer, 0, len(wTee)+1)
		a = append(a, out)
		a = append(a, wTee...)
		wAll = io.MultiWriter(a...)
	}
	return path, writeConfig(wAll, cfg, cmd)
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
	grp.Wait()

	return nil
}
