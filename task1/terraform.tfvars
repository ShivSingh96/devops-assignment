environment = "dev"
owner       = "shivendra"
subnet_id   = "subnet-0123456789abcdef0" # placeholder; replace for a real apply

instances = {
  bastion = {
    instance_type = "t3.micro"
    volume_type   = "gp3"
    volume_size   = 20
  }
  web = {
    instance_type = "t3.small"
    volume_type   = "gp2"
    volume_size   = 30
  }
  app = {
    instance_type = "t3.medium"
    volume_type   = "standard" # distinct from the other four (gp3, gp2, io2, io1)
    volume_size   = 40
  }
  db = {
    instance_type = "m5.large"
    volume_type   = "io2"
    volume_size   = 100
    iops          = 3000
    protected     = true # stateful: see NOTES.md
  }
  batch = {
    instance_type = "c5.large"
    volume_type   = "io1"
    volume_size   = 50
    iops          = 1000
  }
}
