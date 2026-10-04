package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadSecretFiles(t *testing.T) {
	t.Run("loads secret file referenced by _FILE env var", func(t *testing.T) {
		dir := t.TempDir()
		writeSecret(t, filepath.Join(dir, "client-id"), "value-from-file")

		t.Setenv("PRONESTHEUS_NEST_CLIENT_ID_FILE", filepath.Join(dir, "client-id"))
		t.Setenv("PRONESTHEUS_NEST_CLIENT_ID", "")

		loadSecretFiles()

		if got := os.Getenv("PRONESTHEUS_NEST_CLIENT_ID"); got != "value-from-file" {
			t.Fatalf("PRONESTHEUS_NEST_CLIENT_ID = %q, want %q", got, "value-from-file")
		}
	})

	t.Run("trims trailing newline", func(t *testing.T) {
		dir := t.TempDir()
		writeSecret(t, filepath.Join(dir, "owm-auth"), "secret\n")

		t.Setenv("PRONESTHEUS_OWM_AUTH_FILE", filepath.Join(dir, "owm-auth"))
		t.Setenv("PRONESTHEUS_OWM_AUTH", "")

		loadSecretFiles()

		if got := os.Getenv("PRONESTHEUS_OWM_AUTH"); got != "secret" {
			t.Fatalf("PRONESTHEUS_OWM_AUTH = %q, want %q", got, "secret")
		}
	})

	t.Run("no-op when _FILE env var is empty", func(t *testing.T) {
		t.Setenv("PRONESTHEUS_NEST_PROJECT_ID_FILE", "")
		t.Setenv("PRONESTHEUS_NEST_PROJECT_ID", "")

		loadSecretFiles()

		if got := os.Getenv("PRONESTHEUS_NEST_PROJECT_ID"); got != "" {
			t.Fatalf("PRONESTHEUS_NEST_PROJECT_ID = %q, want empty", got)
		}
	})

	t.Run("no-op when secret file does not exist", func(t *testing.T) {
		t.Setenv("PRONESTHEUS_OWM_LOCATION_FILE", filepath.Join(t.TempDir(), "missing"))
		t.Setenv("PRONESTHEUS_OWM_LOCATION", "")

		loadSecretFiles()

		if got := os.Getenv("PRONESTHEUS_OWM_LOCATION"); got != "" {
			t.Fatalf("PRONESTHEUS_OWM_LOCATION = %q, want empty", got)
		}
	})

	t.Run("ignores non _FILE env vars", func(t *testing.T) {
		t.Setenv("PRONESTHEUS_NEST_REFRESH_TOKEN", "direct-value")

		loadSecretFiles()

		if got := os.Getenv("PRONESTHEUS_NEST_REFRESH_TOKEN"); got != "direct-value" {
			t.Fatalf("PRONESTHEUS_NEST_REFRESH_TOKEN = %q, want %q", got, "direct-value")
		}
	})
}

func writeSecret(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
}
