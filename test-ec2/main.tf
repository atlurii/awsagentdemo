resource "aws_instance" "test" {
  ami           = "ami-0c02fb55956c7d316"
  instance_type = "t3.micro"

  tags = {
    Name        = "ci-test-instance"
    Environment = "dev"
  }
}
