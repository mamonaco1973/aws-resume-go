// ==============================================================================
// S3 Storage
// Wraps AWS SDK v2 for file upload and presigned download URL generation.
// Replaces Rails ActiveStorage — the S3 object key is stored directly on
// the Attachment record rather than in intermediate blob tables.
// ==============================================================================
package storage

import (
	"context"
	"fmt"
	"io"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/s3/manager"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

// Client wraps an S3 client and the bucket name.
type Client struct {
	s3     *s3.Client
	bucket string
}

// New creates a storage client using the ECS task's IAM role credentials.
func New(region, bucket string) (*Client, error) {
	cfg, err := awsconfig.LoadDefaultConfig(context.Background(),
		awsconfig.WithRegion(region),
	)
	if err != nil {
		return nil, fmt.Errorf("loading AWS config: %w", err)
	}
	return &Client{s3: s3.NewFromConfig(cfg), bucket: bucket}, nil
}

// Upload streams a file to S3 and returns the object key.
// Uses the multipart upload manager so large files are chunked automatically.
func (c *Client) Upload(ctx context.Context, key string, body io.Reader, contentType string) error {
	uploader := manager.NewUploader(c.s3)
	_, err := uploader.Upload(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(c.bucket),
		Key:         aws.String(key),
		Body:        body,
		ContentType: aws.String(contentType),
	})
	return err
}

// PresignDownload generates a short-lived presigned GET URL for an S3 object.
// The URL is valid for 15 minutes and instructs the browser to download
// the file with the given filename rather than displaying it inline.
func (c *Client) PresignDownload(ctx context.Context, key, filename string) (string, error) {
	presigner := s3.NewPresignClient(c.s3)
	req, err := presigner.PresignGetObject(ctx, &s3.GetObjectInput{
		Bucket:                     aws.String(c.bucket),
		Key:                        aws.String(key),
		ResponseContentDisposition: aws.String(`attachment; filename="` + filename + `"`),
	}, s3.WithPresignExpires(15*time.Minute))
	if err != nil {
		return "", err
	}
	return req.URL, nil
}

// Delete removes an object from S3. Used when an attachment record is deleted.
func (c *Client) Delete(ctx context.Context, key string) error {
	_, err := c.s3.DeleteObject(ctx, &s3.DeleteObjectInput{
		Bucket: aws.String(c.bucket),
		Key:    aws.String(key),
	})
	return err
}
