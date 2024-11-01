package config

const (
	SourceIdent = "FSDS_CONFIG_APPIUM_ENV"
	BackupIdent = "FSDS_CONFIG_APPIUM_ENV_BACKUP"
	TmpCfgIdent = "FSDS_CONFIG_APPIUM_ENV_TEMP"
)

const (
	DefaultiPadSim  = "generic/platform=iOS"
	DefaultEnvQuote = '\''
)

const (
	// The output is separated into 2 vertical regions
	// that separate the syntax placeholder and the usage description:
	//   (Note this may not align correctly in some editors)
	//
	// |     -x, --example ARG ─────╢ The description of the flag may span
	// |                             ║ multiple lines
	// |                             ║ {env:example_var="default value inherited from environment"}
	//
	// The syntax placeholder in the first region is left-aligned and padded
	// so that the entire output is slightly indented.
	// This is done to make the list of flags more readable
	// and associates them underneath an introductory header.

	tablen uint = 8                 // width of a single indentation level
	maxlen uint = 12 * tablen       // maximum width of a line
	numcol uint = 2                 // number of alignable regions in each line
	collen uint = maxlen/numcol - 8 // width of left alignable region
	padlen uint = tablen / 2        // width of left-padding in first region
	synlen uint = collen - padlen   // total width of the first alignable region
	lalign uint = padlen / 2        // first column of the first region
)
