package config

import "strings"

type Type int

const (
	Invalid Type = iota
	Bool
	Int
	Float
	String
	JSON
	Serial
)

func (t Type) String() string {
	switch t {
	case Invalid:
		return "!Type(Invalid)"
	case Bool:
		return "bool"
	case Int:
		return "int"
	case Float:
		return "float"
	case String:
		return "string"
	case JSON:
		return "json"
	case Serial:
		return "serial"
	}
	return ""
}

func ParseType(s string) Type {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "bool":
		return Bool
	case "int":
		return Int
	case "float":
		return Float
	case "string":
		return String
	case "json":
		return JSON
	case "serial":
		return Serial
	}
	return Invalid
}
