// ==============================================================================
// Database
// Opens a GORM connection to PostgreSQL and runs AutoMigrate to create or
// update tables to match the current model structs. AutoMigrate is additive —
// it never drops columns or tables, making it safe to run on every startup.
// ==============================================================================
package db

import (
	"resumescorer/internal/models"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

// Open connects to PostgreSQL and returns a ready GORM instance.
// databaseURL is a standard postgresql:// connection string.
func Open(databaseURL string) (*gorm.DB, error) {
	db, err := gorm.Open(postgres.Open(databaseURL), &gorm.Config{
		// Suppress routine query logs in production; errors still surface.
		Logger: logger.Default.LogMode(logger.Silent),
	})
	if err != nil {
		return nil, err
	}

	if err := migrate(db); err != nil {
		return nil, err
	}

	return db, nil
}

func migrate(db *gorm.DB) error {
	return db.AutoMigrate(
		&models.User{},
		&models.Resume{},
		&models.Folder{},
		&models.Job{},
		&models.Attachment{},
	)
}
