aws_profile = "syed"
aws_region  = "us-east-1"
vpc_cidr    = "10.0.0.0/16"
cidrs       = {
  public1   = "10.0.1.0/24"
  private1  = "10.0.2.0/24"
}

public_key_path  	= "/root/.ssh/kryptonite.pub"
dev_ami         	= "ami-b70554c8"
elb_healthy_threshold   = "2"
elb_unhealthy_threshold = "2"
elb_timeout 		= "3"
elb_interval		= "30"
asg_max 		= "2"
asg_min			= "1"
asg_grace		= "300"
asg_hct			= "EC2"
asg_cap			= "2"
