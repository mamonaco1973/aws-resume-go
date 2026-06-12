# ==============================================================================
# Elastic Container Registry
# ==============================================================================
# Stores the resumescorer Rails Docker image. Mutable tags allow iterative
# builds during development; scan-on-push catches dependency CVEs early.
# ==============================================================================

resource "aws_ecr_repository" "resumescorer" {
  name                 = "resumescorer"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "resumescorer-ecr" }
}
