// ==============================================================================
// Attachment
// A file attached to a scored job stored in S3. The S3Key column holds the
// object key used to generate presigned download URLs. Unlike Rails
// ActiveStorage, there are no intermediate blob tables — the key is stored
// directly on this record.
// ==============================================================================
package models

import "time"

type Attachment struct {
	ID        uint      `gorm:"primarykey"`
	CreatedAt time.Time
	UpdatedAt time.Time

	JobID    uint   `gorm:"not null;index"`
	UserID   uint   `gorm:"not null;index"`
	Filename string `gorm:"not null"`
	// S3Key is the object key used to generate presigned download URLs.
	// Format: attachments/{user_id}/{job_id}/{uuid}_{filename}
	S3Key string `gorm:"not null"`
	Notes string

	Job  Job  `gorm:"foreignKey:JobID"`
	User User `gorm:"foreignKey:UserID"`
}
