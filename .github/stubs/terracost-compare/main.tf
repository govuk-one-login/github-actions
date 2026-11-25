provider "aws" {
  region = "eu-west-2"
}

resource "aws_sqs_queue" "terracost_test" {
  name = "terracost-compare-test"
}
