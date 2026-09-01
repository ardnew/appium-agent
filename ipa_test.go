package main

import (
	"archive/zip"
	"os"
	"path/filepath"
	"testing"

	"howett.net/plist"
)

func writeTestIPA(t *testing.T, entries map[string][]byte) string {
	t.Helper()
	name := filepath.Join(t.TempDir(), "app.ipa")
	file, err := os.Create(name)
	if err != nil {
		t.Fatal(err)
	}
	archive := zip.NewWriter(file)
	for path, data := range entries {
		entry, err := archive.Create(path)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := entry.Write(data); err != nil {
			t.Fatal(err)
		}
	}
	if err := archive.Close(); err != nil {
		t.Fatal(err)
	}
	if err := file.Close(); err != nil {
		t.Fatal(err)
	}
	return name
}

func TestInspectIPABinaryPlist(t *testing.T) {
	data, err := plist.Marshal(map[string]any{"CFBundleIdentifier": "com.example.Custom"}, plist.BinaryFormat)
	if err != nil {
		t.Fatal(err)
	}
	metadata, err := inspectIPA(writeTestIPA(t, map[string][]byte{"Payload/Custom.app/Info.plist": data}))
	if err != nil {
		t.Fatal(err)
	}
	if metadata.BundleID != "com.example.Custom" {
		t.Fatalf("bundle=%q", metadata.BundleID)
	}
}

func TestInspectIPARejectsAmbiguousPayload(t *testing.T) {
	data, _ := plist.Marshal(map[string]any{"CFBundleIdentifier": "com.example.Custom"}, plist.XMLFormat)
	_, err := inspectIPA(writeTestIPA(t, map[string][]byte{
		"Payload/One.app/Info.plist": data,
		"Payload/Two.app/Info.plist": data,
	}))
	if err == nil {
		t.Fatal("multiple application bundles were accepted")
	}
}
