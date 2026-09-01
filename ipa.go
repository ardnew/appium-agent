package main

import (
	"archive/zip"
	"bytes"
	"fmt"
	"io"
	"path"
	"strings"

	"howett.net/plist"
)

const maxInfoPlistSize = 16 << 20

type ipaMetadata struct {
	BundleID string `plist:"CFBundleIdentifier"`
}

func inspectIPA(filename string) (ipaMetadata, error) {
	archive, err := zip.OpenReader(filename)
	if err != nil {
		return ipaMetadata{}, fmt.Errorf("open IPA archive: %w", err)
	}
	defer archive.Close()

	var info *zip.File
	for _, file := range archive.File {
		name := path.Clean(file.Name)
		parts := strings.Split(name, "/")
		if len(parts) == 3 && parts[0] == "Payload" && strings.HasSuffix(parts[1], ".app") && parts[2] == "Info.plist" {
			if info != nil {
				return ipaMetadata{}, fmt.Errorf("IPA contains multiple application bundles")
			}
			info = file
		}
	}
	if info == nil {
		return ipaMetadata{}, fmt.Errorf("IPA does not contain Payload/*.app/Info.plist")
	}
	if info.UncompressedSize64 > maxInfoPlistSize {
		return ipaMetadata{}, fmt.Errorf("IPA Info.plist is too large")
	}

	r, err := info.Open()
	if err != nil {
		return ipaMetadata{}, fmt.Errorf("open IPA Info.plist: %w", err)
	}
	defer r.Close()
	data, err := io.ReadAll(io.LimitReader(r, maxInfoPlistSize+1))
	if err != nil {
		return ipaMetadata{}, fmt.Errorf("read IPA Info.plist: %w", err)
	}
	if len(data) > maxInfoPlistSize {
		return ipaMetadata{}, fmt.Errorf("IPA Info.plist is too large")
	}
	var metadata ipaMetadata
	if err := plist.NewDecoder(bytes.NewReader(data)).Decode(&metadata); err != nil {
		return ipaMetadata{}, fmt.Errorf("decode IPA Info.plist: %w", err)
	}
	metadata.BundleID = strings.TrimSpace(metadata.BundleID)
	if metadata.BundleID == "" {
		return ipaMetadata{}, fmt.Errorf("IPA application bundle identifier is empty")
	}
	return metadata, nil
}
