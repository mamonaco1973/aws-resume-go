// ==============================================================================
// Folder
// A named bucket for organising jobs on the dashboard. Purely cosmetic —
// scoring is unaffected by folder assignment. Deleting a folder sets
// folder_id = NULL on its jobs rather than removing them.
// ==============================================================================
package models

import "time"

type Folder struct {
	ID        uint      `gorm:"primarykey"`
	CreatedAt time.Time
	UpdatedAt time.Time

	UserID uint   `gorm:"not null;index"`
	Name   string `gorm:"not null"`

	// SET NULL preserves jobs when a folder is deleted.
	Jobs []Job `gorm:"foreignKey:FolderID;constraint:OnDelete:SET NULL"`
}
