// ==============================================================================
// User
// Represents one authenticated account. bcrypt handles password hashing.
// Every other resource (resumes, jobs, folders, attachments) has a UserID
// foreign key so users can never see each other's data.
// ==============================================================================
package models

import (
	"time"

	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

type User struct {
	ID        uint      `gorm:"primarykey"`
	CreatedAt time.Time
	UpdatedAt time.Time

	Email          string `gorm:"uniqueIndex;not null"`
	PasswordHash   string `gorm:"not null"`
	TokenLimit     int    `gorm:"not null;default:100000"`
	TokensUsed     int    `gorm:"not null;default:0"`

	// Reset token is hashed before storage; expires after 2 hours.
	ResetPasswordToken  string
	ResetPasswordSentAt *time.Time

	// Cascade deletes to all child records when a user is removed.
	Resumes     []Resume     `gorm:"foreignKey:UserID;constraint:OnDelete:CASCADE"`
	Folders     []Folder     `gorm:"foreignKey:UserID;constraint:OnDelete:CASCADE"`
	Jobs        []Job        `gorm:"foreignKey:UserID;constraint:OnDelete:CASCADE"`
	Attachments []Attachment `gorm:"foreignKey:UserID;constraint:OnDelete:CASCADE"`
}

// SetPassword hashes the plain-text password with bcrypt and stores it.
func (u *User) SetPassword(plain string) error {
	hash, err := bcrypt.GenerateFromPassword([]byte(plain), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	u.PasswordHash = string(hash)
	return nil
}

// CheckPassword returns true when the plain-text password matches the hash.
func (u *User) CheckPassword(plain string) bool {
	err := bcrypt.CompareHashAndPassword([]byte(u.PasswordHash), []byte(plain))
	return err == nil
}

// OverTokenLimit returns true when the user has consumed their Bedrock budget.
func (u *User) OverTokenLimit() bool {
	return u.TokensUsed >= u.TokenLimit
}

// TokenUsagePct returns the percentage of the token budget consumed, capped at 100.
// Used to drive the SVG ring chart on the dashboard.
func (u *User) TokenUsagePct() int {
	if u.TokenLimit == 0 {
		return 0
	}
	pct := int(float64(u.TokensUsed) / float64(u.TokenLimit) * 100)
	if pct > 100 {
		return 100
	}
	return pct
}

// AccumulateTokens atomically increments the user's token counter.
// The raw SQL UPDATE avoids the read-modify-write race that would occur
// if two concurrent scoring jobs both read then write tokens_used.
func AccumulateTokens(db *gorm.DB, userID uint, total int) error {
	if total <= 0 {
		return nil
	}
	return db.Model(&User{}).Where("id = ?", userID).
		UpdateColumn("tokens_used", gorm.Expr("tokens_used + ?", total)).Error
}
