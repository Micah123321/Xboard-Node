package kernel

import (
	"encoding/base64"
	"fmt"
	"strings"

	"github.com/cedar2025/xboard-node/internal/panel"
)

// ValidateShadowsocks2022Credentials checks server and user credentials before
// they are passed into kernel-specific config builders. SS2022 requires
// standard base64 keys with a cipher-specific decoded length.
func ValidateShadowsocks2022Credentials(nc *panel.NodeConfig, users []panel.User) error {
	if nc == nil || nc.Protocol != "shadowsocks" || !strings.HasPrefix(nc.Cipher, "2022-blake3-") {
		return nil
	}

	keyLength, err := shadowsocks2022KeyLength(nc.Cipher)
	if err != nil {
		return err
	}

	if err := validateShadowsocks2022Key(nc.ServerKey, keyLength); err != nil {
		return fmt.Errorf("invalid shadowsocks 2022 server_key: %w", err)
	}

	for _, user := range users {
		if err := validateShadowsocks2022Key(user.UUID, keyLength); err != nil {
			return fmt.Errorf("invalid shadowsocks 2022 user password for user_id=%d: %w", user.ID, err)
		}
	}

	return nil
}

func shadowsocks2022KeyLength(cipher string) (int, error) {
	switch cipher {
	case "2022-blake3-aes-128-gcm":
		return 16, nil
	case "2022-blake3-aes-256-gcm", "2022-blake3-chacha20-poly1305":
		return 32, nil
	default:
		return 0, fmt.Errorf("unsupported shadowsocks 2022 cipher %q", cipher)
	}
}

func validateShadowsocks2022Key(value string, keyLength int) error {
	if value == "" {
		return fmt.Errorf("empty value, expected standard base64 for a %d-byte key", keyLength)
	}

	decoded, err := base64.StdEncoding.DecodeString(value)
	if err != nil {
		return fmt.Errorf("must be standard base64 for a %d-byte key: %w", keyLength, err)
	}

	if len(decoded) != keyLength {
		return fmt.Errorf("expected %d-byte key after base64 decode, got %d bytes", keyLength, len(decoded))
	}

	return nil
}
