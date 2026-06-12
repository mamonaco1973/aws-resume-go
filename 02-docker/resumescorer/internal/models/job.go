// ==============================================================================
// Job
// Represents one resume-vs-job scoring request. Tracks the full lifecycle
// from submission through async Asynq processing to a final score and
// written analysis.
//
// Status flow:  pending → scoring → scored
//                               ↘ error
//
// FolderID and Score use pointer types so they can be NULL in the database.
// ==============================================================================
package models

import "time"

type Job struct {
	ID        uint      `gorm:"primarykey"`
	CreatedAt time.Time
	UpdatedAt time.Time

	UserID   uint  `gorm:"not null;index"`
	ResumeID *uint `gorm:"index"`
	// Pointer type allows NULL — a job does not need to belong to a folder.
	FolderID *uint `gorm:"index"`

	Title               string `gorm:"default:''"`
	Company             string `gorm:"default:''"`
	SourceType          string `gorm:"not null"`
	URL                 string
	RawText             string `gorm:"type:text"`
	JobDescriptionText  string `gorm:"type:text"`
	// Pointer type allows NULL until scoring completes.
	Score               *int
	Analysis            string `gorm:"type:text"`
	Status              string `gorm:"not null;default:'pending';index"`
	StatusMessage       string `gorm:"default:''"`
	Notes               string `gorm:"type:text"`

	Resume      *Resume      `gorm:"foreignKey:ResumeID"`
	Folder      *Folder      `gorm:"foreignKey:FolderID"`
	Attachments []Attachment `gorm:"foreignKey:JobID;constraint:OnDelete:CASCADE"`
}

// Processing returns true for both "pending" (queued) and "scoring" (in flight).
// Both mean the job has not yet reached a terminal state.
func (j *Job) Processing() bool {
	return j.Status == "pending" || j.Status == "scoring"
}

func (j *Job) Scored() bool { return j.Status == "scored" }
func (j *Job) Errored() bool { return j.Status == "error" }

// ScoreColor returns "green", "yellow", or "red" for the score badge CSS class.
func (j *Job) ScoreColor() string {
	if !j.Scored() || j.Score == nil {
		return "gray"
	}
	switch {
	case *j.Score >= 75:
		return "green"
	case *j.Score >= 50:
		return "yellow"
	default:
		return "red"
	}
}

// ScoreVal returns the score as an int (0 if nil). Used in templates where
// Go templates cannot dereference *int directly for function calls.
func (j *Job) ScoreVal() int {
	if j.Score == nil {
		return 0
	}
	return *j.Score
}

// FolderIDVal returns folder_id as uint (0 if nil). Used in templates to
// compare nullable foreign keys with option values.
func (j *Job) FolderIDVal() uint {
	if j.FolderID == nil {
		return 0
	}
	return *j.FolderID
}
