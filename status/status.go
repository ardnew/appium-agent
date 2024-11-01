package status

import (
	"errors"
)

var (
	ErrOpenFile  = errors.New("failed to open file")
	ErrReadFile  = errors.New("failed to read file")
	ErrWriteFile = errors.New("failed to write file")
)

var (
	ErrInvalidConfig = errors.New("invalid configuration path")
	ErrInvalidBackup = errors.New("invalid configuration backup path")
	ErrIdentUndef    = errors.New("undefined configuration parameter")
	ErrTypeUndef     = errors.New("undefined configuration type")
)

var (
	ErrParseShebang  = errors.New("invalid shebang on line 1")
	ErrInvalidScript = errors.New("invalid script path")
	ErrInvalidShell  = errors.New("invalid shell path")
)
