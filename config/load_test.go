package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestOverrideFileUsesCurrentConfigButPreservesFlags(t *testing.T) {
	t.Setenv("target_app_ipa", "/cache/stale.ipa")
	env := DefaultEnv()
	app, _ := env.Get(func(v *Var) bool { return v.Ident == "bundled_app" })
	source, _ := env.Get(func(v *Var) bool { return v.Ident == "proj_source" })
	ipa, _ := env.Get(func(v *Var) bool { return v.Ident == "target_app_ipa" })
	if err := source.Set("/flag/project.xcodeproj"); err != nil {
		t.Fatal(err)
	}
	source.UserDef = true
	path := filepath.Join(t.TempDir(), "config.env")
	data := "export bundled_app='com.example.Upload'\nexport proj_source='/stale/project.xcodeproj'\nunset -v target_app_ipa\n"
	if err := os.WriteFile(path, []byte(data), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := env.OverrideFile(path); err != nil {
		t.Fatal(err)
	}
	if app.String() != "com.example.Upload" {
		t.Fatalf("bundled_app=%q", app.String())
	}
	if source.String() != "/flag/project.xcodeproj" {
		t.Fatalf("flag source overwritten: %q", source.String())
	}
	if ipa.String() != "" {
		t.Fatalf("stale inherited target_app_ipa retained: %q", ipa.String())
	}
}
