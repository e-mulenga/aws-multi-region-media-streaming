terraform {
  required_version = ">= 1.0"

  backend "s3" {
    bucket       = "<landing-zone-state-bucket>"
    key          = "<landing-zone-state-bucket-region>"
    region       = "your-bucket-region"
    use_lockfile = true
    encrypt      = true
  }
}
