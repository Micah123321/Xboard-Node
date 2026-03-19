package kernel

import (
	"strings"
	"testing"

	"github.com/cedar2025/xboard-node/internal/panel"
)

func TestValidateShadowsocks2022Credentials_ValidAES128(t *testing.T) {
	nc := &panel.NodeConfig{
		Protocol:  "shadowsocks",
		Cipher:    "2022-blake3-aes-128-gcm",
		ServerKey: "MDEyMzQ1Njc4OWFiY2RlZg==",
	}
	users := []panel.User{
		{ID: 1, UUID: "MDEyMzQ1Njc4OWFiY2RlZg=="},
		{ID: 2, UUID: "ZmVkY2JhOTg3NjU0MzIxMA=="},
	}

	if err := ValidateShadowsocks2022Credentials(nc, users); err != nil {
		t.Fatalf("expected valid credentials, got %v", err)
	}
}

func TestValidateShadowsocks2022Credentials_InvalidServerKey(t *testing.T) {
	nc := &panel.NodeConfig{
		Protocol:  "shadowsocks",
		Cipher:    "2022-blake3-aes-128-gcm",
		ServerKey: "not-base64",
	}
	users := []panel.User{{ID: 1, UUID: "MDEyMzQ1Njc4OWFiY2RlZg=="}}

	err := ValidateShadowsocks2022Credentials(nc, users)
	if err == nil {
		t.Fatal("expected error, got nil")
	}
	if !strings.Contains(err.Error(), "server_key") {
		t.Fatalf("expected server_key in error, got %v", err)
	}
	if !strings.Contains(err.Error(), "standard base64") {
		t.Fatalf("expected base64 guidance in error, got %v", err)
	}
}

func TestValidateShadowsocks2022Credentials_InvalidUserPassword(t *testing.T) {
	nc := &panel.NodeConfig{
		Protocol:  "shadowsocks",
		Cipher:    "2022-blake3-aes-128-gcm",
		ServerKey: "MDEyMzQ1Njc4OWFiY2RlZg==",
	}
	users := []panel.User{{ID: 42, UUID: "875-jk6wtj"}}

	err := ValidateShadowsocks2022Credentials(nc, users)
	if err == nil {
		t.Fatal("expected error, got nil")
	}
	if !strings.Contains(err.Error(), "user_id=42") {
		t.Fatalf("expected user id in error, got %v", err)
	}
	if !strings.Contains(err.Error(), "standard base64") {
		t.Fatalf("expected base64 guidance in error, got %v", err)
	}
}

func TestValidateShadowsocks2022Credentials_InvalidLength(t *testing.T) {
	nc := &panel.NodeConfig{
		Protocol:  "shadowsocks",
		Cipher:    "2022-blake3-aes-256-gcm",
		ServerKey: "MDEyMzQ1Njc4OWFiY2RlZg==",
	}
	users := []panel.User{{ID: 1, UUID: "MDEyMzQ1Njc4OWFiY2RlZmdoaWprbG1ub3BxcnN0dXY="}}

	err := ValidateShadowsocks2022Credentials(nc, users)
	if err == nil {
		t.Fatal("expected error, got nil")
	}
	if !strings.Contains(err.Error(), "expected 32-byte key") {
		t.Fatalf("expected key length hint in error, got %v", err)
	}
}
