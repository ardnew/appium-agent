package config

import (
	"fmt"
	"os"
	"slices"
	"strings"

	"github.com/muesli/reflow/indent"
	"github.com/muesli/reflow/wordwrap"
)

type Env []*Var

type Order func(a, b *Var) int

func DefaultEnv() Env {
	// Define the default environment variable / command-line flags.
	env := make(Env, 0, 32)
	env = append(env, NewVar("sdk-version", "k", "sdk_version", String,
		"$( xcrun --sdk iphoneos --show-sdk-version )",
		"Specify the iOS/iPadOS SDK platform `version` used by WebDriverAgent compilation host",
		"(see: xcrun(1), xcode-select(1))"))
	env = append(env, NewVar("ios-version", "o", "ios_version", String,
		"13.2",
		"Specify the deployment target iOS/iPadOS `version`",
		"(build setting: IPHONEOS_DEPLOYMENT_TARGET)"))
	env = append(env, NewVar("target-app-source", "p", "proj_source", String,
		"",
		"Directory `path` of the target app source code"))
	env = append(env, NewVar("build-config", "c", "proj_config", String,
		"Release",
		"Build target app using `config` from the selected scheme defined in Xcode project file"))
	env = append(env, NewVar("build-scheme", "s", "proj_scheme", String,
		"FMPS Calculator",
		"Build target app using `scheme` defined in Xcode project file"))
	env = append(env, NewVar("test-driver-config", "C", "test_config", String,
		"Release",
		"Build test driver using `config` from the selected scheme defined in Xcode project file"))
	env = append(env, NewVar("test-driver-scheme", "S", "test_scheme", String,
		"FMPS Calculator",
		"Build test driver using `scheme` defined in Xcode project file"))
	env = append(env, NewVar("target-app-bundle", "a", "bundled_app", String,
		"com.NorthropGrumman.FMPS-Calculator.App",
		"Bundle `ID` of the target app"))
	env = append(env, NewVar("test-driver-bundle", "b", "bundled_drv", String,
		"com.NorthropGrumman.FMPS-Test-Driver.App",
		"Bundle `ID` of the WebDriverAgent service"))
	env = append(env, NewVar("target-device", "d", "target_dest", String,
		"id=00008101-0005499E010B001E",
		"Target `UUID` of the device under test"))
	// env = append(env, NewVar("wda-network", "n", "driver_name", String,
	// 	"en0",
	// 	"Start WebDriverAgent that is reachable via host network `interface`"))
	env = append(env, NewVar("wda-port", "t", "driver_port", Int,
		8100,
		"Connect to WebDriverAgent listening on TCP `port`"))
	env = append(env, NewVar("listen-network", "n", "listen_name", String,
		"en5",
		"Network `interface` of the Appium REST server"))
	env = append(env, NewVar("listen-port", "l", "listen_port", Int,
		4723,
		"TCP `port` of the Appium REST server"))
	env = append(env, NewVar("xcodebuild-action", "x", "xcbuild_act", String,
		"test",
		"Run xcodebuild(1) `action` on the target app source code"))
	env = append(env, NewVar("trace", "g", "trace_agent", Bool,
		false,
		"Print each command in the Appium init script before it is executed",
		"(useful for debugging)"))
	return env
}

// Override will replace values in the configuration envionment
// according to the policy given by command-line flags --orphan and --zero.
func (e Env) Override(orphan, zero bool) Env {
	for i, v := range e {
		if v.UserDef {
			// Never override user-defined values given on the command-line.
			continue
		}
		if zero {
			// Zero will remove all default values.
			e[i].Zero = true
			e[i].Value = nil
		}
		if orphan {
			// Orphan will prevent environment inheritance.
			e[i].Orphan = true
			e[i].EnvValue = nil
		} else {
			if val, ok := os.LookupEnv(v.Ident); ok {
				if err := e[i].Set(val); err != nil {
					fmt.Fprintf(
						os.Stderr,
						"warning: cannot inherit %q from env as flag %q: %v\n",
						v.Ident, v.Flag, err,
					)
				}
			}
		}
	}
	return e
}

func orderByFlag(a, b *Var) int {
	return strings.Compare(a.Flag, b.Flag)
}

func (e Env) Sort(o Order) Env {
	slices.SortStableFunc(e, o)
	return e
}

func (e Env) Get(want func(*Var) bool) (*Var, bool) {
	for i := range e {
		if want(e[i]) {
			return e[i], true
		}
	}
	return nil, false
}

func (e Env) Usage(program, version string, flag ...*Var) func() {
	return func() {
		ctrlText := []string{
			fmt.Sprintf("The following flags control how %s itself operates.", program),
		}
		servText := []string{
			"The following flags affect the Appium service.",
			"In particular, you can control which version of the FMPS Calculator " +
				"app to test as well as on which iPad device to install the app and run " +
				"automated tests.",
			"Other options allow tuning the test drivers (XCUITest, WebDriverAgent) " +
				"and the JSON test capabilities supported by TestComplete.",
		}
		format := func(text ...string) string {
			const width = maxlen - lalign
			return indent.String(wordwrap.String(strings.Join(text, "\n\n"), int(width)), lalign)
		}

		fmt.Println(program + " version " + version)
		fmt.Println()
		fmt.Println("USAGE")
		fmt.Println()
		fmt.Println(indent.String(program+" [flags]", lalign))
		fmt.Println()
		fmt.Println("FLAGS")
		fmt.Println()
		fmt.Println(format(ctrlText...))
		fmt.Println()
		for i, v := range flag {
			if i > 0 {
				fmt.Println()
			}
			fmt.Println(v.Usage())
		}
		fmt.Println()
		fmt.Println(format(servText...))
		fmt.Println()
		for i, v := range e {
			if i > 0 {
				fmt.Println()
			}
			fmt.Println(v.Usage())
		}
	}
}
