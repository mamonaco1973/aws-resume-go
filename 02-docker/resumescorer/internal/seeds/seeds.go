// ==============================================================================
// Seeds
// Populates the database with a demo user, resumes, folders, and pre-scored
// jobs. Idempotent — safe to call on every container start. Mirrors the
// logic in the original db/seeds.rb.
// ==============================================================================
package seeds

import (
	"fmt"
	"resumescorer/internal/models"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

func Run(db *gorm.DB) error {
	fmt.Println("NOTE: Seeding demo user...")

	var demo models.User
	result := db.Where("email = ?", "demo@example.com").First(&demo)
	if result.Error == gorm.ErrRecordNotFound {
		demo = models.User{
			Email:      "demo@example.com",
			TokenLimit: 100_000,
			TokensUsed: 0,
		}
		if err := demo.SetPassword("password123"); err != nil {
			return err
		}
		if err := db.Create(&demo).Error; err != nil {
			return err
		}
	} else if result.Error != nil {
		return result.Error
	}

	fmt.Println("NOTE: Seeding demo resumes...")

	var resumeCount int64
	db.Model(&models.Resume{}).Where("user_id = ?", demo.ID).Count(&resumeCount)
	if resumeCount == 0 {
		r1 := models.Resume{
			UserID: demo.ID,
			Name:   "Software Engineer Resume",
			ContentText: `Jane Smith
Software Engineer | jane@example.com | github.com/janesmith

EXPERIENCE
Senior Software Engineer - Acme Corp (2020-present)
- Led migration of monolithic Rails app to microservices, reducing p99
  latency by 40%
- Designed and shipped real-time notification system serving 500K users
- Mentored 3 junior engineers and conducted weekly code reviews

Software Engineer - StartupCo (2017-2020)
- Built REST API with Ruby on Rails and PostgreSQL, serving 1M req/day
- Implemented CI/CD pipeline with GitHub Actions and Docker

SKILLS
Ruby, Rails, Python, Go, PostgreSQL, Redis, AWS (ECS, Lambda, S3, RDS),
Terraform, Docker, Kubernetes

EDUCATION
B.S. Computer Science - State University (2017)`,
		}
		if err := db.Create(&r1).Error; err != nil {
			return err
		}

		r2 := models.Resume{
			UserID: demo.ID,
			Name:   "Data Engineer Resume",
			ContentText: `Jane Smith
Data Engineer | jane@example.com

EXPERIENCE
Data Engineer - BigData Inc (2021-present)
- Built ETL pipelines processing 10TB/day using Apache Spark and Airflow
- Designed Snowflake data warehouse schema for analytics team
- Reduced pipeline failure rate from 15% to 0.5%

Junior Data Analyst - Corp Analytics (2018-2021)
- Created Tableau dashboards consumed by C-suite weekly
- Automated Excel reporting with Python, saving 20 hours/week

SKILLS
Python, SQL, Spark, Airflow, Snowflake, dbt, AWS Glue, Redshift, Tableau

EDUCATION
B.S. Statistics - State University (2018)`,
		}
		if err := db.Create(&r2).Error; err != nil {
			return err
		}
	}

	fmt.Println("NOTE: Seeding demo folders...")

	// Upsert by name so re-running seeds never creates duplicates.
	techFolder := models.Folder{UserID: demo.ID, Name: "Tech Companies"}
	db.Clauses(clause.OnConflict{DoNothing: true}).
		Where("user_id = ? AND name = ?", demo.ID, "Tech Companies").
		FirstOrCreate(&techFolder)

	startupsFolder := models.Folder{UserID: demo.ID, Name: "Startups"}
	db.Clauses(clause.OnConflict{DoNothing: true}).
		Where("user_id = ? AND name = ?", demo.ID, "Startups").
		FirstOrCreate(&startupsFolder)

	fmt.Println("NOTE: Seeding demo jobs...")

	var jobCount int64
	db.Model(&models.Job{}).Where("user_id = ?", demo.ID).Count(&jobCount)
	if jobCount == 0 {
		var firstResume models.Resume
		if err := db.Where("user_id = ?", demo.ID).First(&firstResume).Error; err != nil {
			return err
		}

		score82 := 82
		score61 := 61

		jobs := []models.Job{
			{
				UserID:             demo.ID,
				ResumeID:           &firstResume.ID,
				FolderID:           &techFolder.ID,
				Title:              "Senior Rails Engineer",
				Company:            "Acme Corp",
				SourceType:         "raw_text",
				RawText:            "Seeking an experienced Rails engineer with 5+ years experience.",
				JobDescriptionText: "Senior Rails Engineer at Acme Corp. 5+ years Rails, AWS, PostgreSQL.",
				Score:              &score82,
				Analysis:           "Overview: Strong match. Candidate's Rails background aligns well with the role.\n\nStrengths: Direct Rails experience, AWS familiarity, and team leadership are all directly relevant.\n\nWeaknesses: No Kubernetes experience listed; the role lists it as preferred.",
				Status:             "scored",
			},
			{
				UserID:             demo.ID,
				ResumeID:           &firstResume.ID,
				FolderID:           &techFolder.ID,
				Title:              "Backend Engineer",
				Company:            "TechCorp",
				SourceType:         "raw_text",
				RawText:            "Looking for a backend engineer with Go and PostgreSQL experience.",
				JobDescriptionText: "Backend Engineer at TechCorp. Go and PostgreSQL required, 3+ years.",
				Score:              &score61,
				Analysis:           "Overview: Partial match. Candidate has strong database skills but limited Go experience.\n\nStrengths: PostgreSQL experience and API design background are directly applicable.\n\nWeaknesses: Go is not a primary skill; the role requires 3+ years of Go experience.",
				Status:             "scored",
			},
		}

		for _, j := range jobs {
			if err := db.Create(&j).Error; err != nil {
				return err
			}
		}
	}

	fmt.Println("NOTE: Seeding complete.")
	return nil
}
