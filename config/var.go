package config

import (
	"bytes"
	"fmt"
	"os"
	"slices"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/muesli/reflow/indent"

	"github.com/ardnew/appium-agent/status"
)

type Var struct {
	Flag     string // long flag ("--flag")
	PFlag    string // short flag ("-f")
	Ident    string
	Comment  []string
	VType    Type
	Aggr     bool
	UserDef  bool
	Zero     bool
	Orphan   bool
	Value    any
	EnvValue any
}

func NewVar(long, short, ident string, t Type, value any, comment ...string) *Var {
	return &Var{
		Flag: long, PFlag: short, Ident: ident, VType: t, Aggr: false, Value: value, EnvValue: os.Getenv(ident), Comment: comment,
	}
}

func NewAggregrateVar(long, short, ident string, t Type, comment ...string) *Var {
	return &Var{
		Flag: long, PFlag: short, Ident: ident, VType: t, Aggr: true, Value: nil, EnvValue: nil, Comment: comment,
	}
}

func (v *Var) IsBoolFlag() bool {
	return v.VType == Bool
}

func (v *Var) String() string {
	switch v.VType {
	case Invalid:
		return ""
	case Bool:
		return encode(v, strconv.FormatBool)
	case Int:
		return encode(v, strconv.Itoa)
	case Float:
		return encode(v, encodeFloat)
	case String:
		return encode(v, func(s string) string { return s })
	case JSON:
		return encode(v, encodeJSON)
	case Serial:
		return encode(v, encodeSerial)
	}
	return ""
}

func (v *Var) Set(s string) error {
	switch v.VType {
	case Invalid:
		return fmt.Errorf("invalid type: %w", status.ErrTypeUndef)
	case Bool:
		return decode(v, s, strconv.ParseBool)
	case Int:
		return decode(v, s, strconv.Atoi)
	case Float:
		return decode(v, s, decodeFloat)
	case String:
		return decode(v, s, func(s string) (string, error) { return s, nil })
	case JSON:
		return decode(v, s, decodeJSON(v))
	case Serial:
		return decode(v, s, decodeSerial(v))
	}
	return nil
}

func (v *Var) Type() string { return v.VType.String() }

func (v *Var) Usage() string {
	var top, buf bytes.Buffer
	name, usage := v.parseFlagUsage()
	for range padlen {
		top.WriteRune(' ')
	}

	top.Write(v.syntax([]string{"-" + v.PFlag, "--" + v.Flag}, name, synlen-1))
	top.Write(v.connector(int(collen)-utf8.RuneCount(top.Bytes()), usage))
	buf.Write(v.usage(wrap(maxlen, top.Bytes()), v.inherit(0, 0), collen, maxlen))

	return buf.String()
}

func (v *Var) syntax(alt []string, arg string, maxlen uint) []byte {
	alt = Filter(slices.Values(alt),
		func(s string) bool { return strings.TrimSpace(s) != "" })
	if len(alt) == 0 {
		return nil
	}
	if v.VType == Bool {
		arg = ""
	} else {
		if arg == "" {
			arg = v.VType.String()
		}
		arg = " " + strings.ToUpper(arg)
	}
	for i := range alt {
		s := strings.Join(alt[i:], ", ") + arg
		if uint(utf8.RuneCountInString(s)) <= maxlen { //nolint:gosec
			return []byte(s)
		}
	}
	return v.syntax(alt[:len(alt)-1], arg, maxlen)
}

func (v *Var) connector(width int, usage string) []byte {
	var buf bytes.Buffer
	buf.WriteRune(' ')
	if width > 1 {
		if width > 2 {
			for col := width; col > 3; col-- {
				buf.WriteRune('─')
			}
			buf.WriteRune('╥')
		}
		buf.WriteRune(' ')
	}
	buf.WriteString(usage)
	return buf.Bytes()
}

func (v *Var) usage(fullText []byte, inherit []byte, shift, width uint) []byte {
	appendLine := func(prefix, line []byte, column uint) []byte {
		var buf bytes.Buffer
		buf.WriteRune('\n')
		buf.Write(indent.Bytes(append(prefix, line...), column))
		return buf.Bytes()
	}
	const (
		pipe = "║ "
		tail = "╙── "
	)

	var buf bytes.Buffer
	if idx := strings.Index(string(fullText), "\n"); idx < 0 {
		buf.Write(fullText)
	} else {
		buf.Write(fullText[:idx])
		row := bytes.Split(wrap(width-shift, fullText[idx+1:]), []byte("\n"))
		for _, r := range row {
			buf.Write(appendLine([]byte(pipe), r, shift-2))
		}
	}
	if len(inherit) > 0 {
		buf.Write(appendLine([]byte(tail), inherit, shift-2))
	}
	return buf.Bytes()
}

func (v *Var) inherit(shift, width uint) []byte {
	var buf bytes.Buffer
	if v.Ident != "" {
		exp := v.Ident
		if def := v.String(); def != "" {
			exp += "=" + fmt.Sprintf("%q", def)
		}
		// If we aren't formatting the output,
		// just return the environment variable/default value.
		if shift == 0 && width == 0 {
			return []byte("{env:" + exp + "}")
		}
		row := indent.Bytes([]byte(" → "), shift)
		row = append(row, indent.Bytes(wrap(width-shift, []byte("{env:"+exp+"}")), 0)...)
		buf.WriteRune('\n')
		buf.Write(row)
	}
	return buf.Bytes()
}

func (v *Var) parseFlagUsage() (name string, usage string) {
	// Look for a back-quoted name, but avoid the strings package.
	usage = strings.Join(v.Comment, "\n")
	for i := 0; i < len(usage); i++ {
		if usage[i] == '`' {
			for j := i + 1; j < len(usage); j++ {
				if usage[j] == '`' {
					name = strings.ToUpper(usage[i+1 : j])
					usage = usage[:i] + name + usage[j+1:]
					return name, usage
				}
			}
			break // Only one back quote; use type name.
		}
	}
	return strings.ToUpper(v.VType.String()), usage
}
