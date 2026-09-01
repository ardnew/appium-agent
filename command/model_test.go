package command

import "testing"

func TestMode(t *testing.T) {
	tests := []struct {
		name string
		cmd  Model
		want string
	}{
		{"full", Model{}, ModeFull},
		{"restart", Model{SkipBuild: true}, ModeRestart},
		{"driver only", Model{TestDriverOnly: true}, ModeTestDriverOnly},
		{"driver relaunch", Model{RelaunchTestDriver: true}, ModeRelaunchTestDriver},
		{"activate IPA", Model{ActivateIPA: "/tmp/app.ipa"}, ModeActivateIPA},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			got, err := test.cmd.Mode()
			if err != nil || got != test.want {
				t.Fatalf("Mode()=(%q,%v), want (%q,nil)", got, err, test.want)
			}
		})
	}
	if _, err := (Model{SkipBuild: true, TestDriverOnly: true}).Mode(); err == nil {
		t.Fatal("conflicting modes were accepted")
	}
}
