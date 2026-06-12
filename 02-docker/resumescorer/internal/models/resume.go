// ==============================================================================
// Resume
// Stores one plain-text resume for a user. Deleting a resume sets
// resume_id = NULL on associated jobs (nullify) rather than deleting them —
// scoring history is preserved even if the source resume is removed.
// ==============================================================================
package models

import "time"

type Resume struct {
	ID        uint      `gorm:"primarykey"`
	CreatedAt time.Time
	UpdatedAt time.Time

	UserID      uint   `gorm:"not null;index"`
	Name        string `gorm:"not null"`
	ContentText string `gorm:"not null;type:text"`

	// SET NULL preserves job scoring history when a resume is deleted.
	Jobs []Job `gorm:"foreignKey:ResumeID;constraint:OnDelete:SET NULL"`
}
