// ==============================================================================
// Config
// Loads all runtime configuration from environment variables injected by
// the ECS task definition from Secrets Manager. Panics on startup if any
// required value is missing so misconfiguration fails loudly.
// ==============================================================================
package config

import (
	"fmt"
	"os"
)

type Config struct {
	DatabaseURL    string
	RedisURL       string
	SecretKeyBase  string
	BedrockModelID string
	S3Bucket       string
	AWSRegion      string
	Port           string

	SMTPServer   string
	SMTPPort     string
	SMTPUser     string
	SMTPPassword string
	AppHostname  string
}

func Load() *Config {
	cfg := &Config{
		DatabaseURL:    mustEnv("DATABASE_URL"),
		RedisURL:       mustEnv("REDIS_URL"),
		SecretKeyBase:  mustEnv("SECRET_KEY_BASE"),
		BedrockModelID: getEnv("BEDROCK_MODEL_ID", "us.anthropic.claude-haiku-4-5-20251001-v1:0"),
		S3Bucket:       mustEnv("S3_BUCKET_NAME"),
		AWSRegion:      getEnv("AWS_REGION", "us-east-1"),
		Port:           getEnv("PORT", "3000"),

		SMTPServer:   getEnv("SMTP_SERVER", ""),
		SMTPPort:     getEnv("SMTP_PORT", "587"),
		SMTPUser:     getEnv("SMTP_USER", ""),
		SMTPPassword: getEnv("SMTP_PASSWORD", ""),
		AppHostname:  getEnv("APP_HOST", "localhost:3000"),
	}
	return cfg
}

func mustEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		panic(fmt.Sprintf("required environment variable %s is not set", key))
	}
	return v
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
