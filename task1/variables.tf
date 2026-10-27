variable "region" {
  type    = string
  default = "us-east-1"
}

variable "instances" {
  description = "Map of instance name => settings. One entry per EC2 instance."
  type = map(object({
    instance_type = string
    volume_type   = string
    volume_size   = number
    iops          = optional(number)      # required for io1/io2
    protected     = optional(bool, false) # true => created by the prevent_destroy resource
  }))

  # io1/io2 volumes fail at apply time without iops; catch it at plan time instead
  validation {
    condition = alltrue([
      for v in values(var.instances) :
      contains(["io1", "io2"], v.volume_type) ? v.iops != null : true
    ])
    error_message = "io1/io2 volumes require iops to be set."
  }

  # the assignment requires at least one provisioned-IOPS volume
  validation {
    condition     = anytrue([for v in values(var.instances) : contains(["io1", "io2"], v.volume_type)])
    error_message = "At least one instance must use an io1 or io2 root volume."
  }

  # prevent_destroy is per resource block, so exactly one protected instance keeps the intent clear
  validation {
    condition     = length([for v in values(var.instances) : v if v.protected]) == 1
    error_message = "Exactly one instance must have protected = true."
  }
}

variable "environment" {
  type = string
}

variable "owner" {
  type = string
}

variable "subnet_id" {
  type = string
}
