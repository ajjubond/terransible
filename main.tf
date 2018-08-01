[root@localhost terra]# cat main.tf
provider "aws" {
  region  = "${var.aws_region}"
  profile = "${var.aws_profile}"
}


#------------VPC-----------

resource "aws_vpc" "wp_vpc" {
   cidr_block = "${var.vpc_cidr}"
    tags {
     Name = "wp_vpc"
    }
}

#internet gateway

resource "aws_internet_gateway" "wp_internet_gateway" {
  vpc_id = "${aws_vpc.wp_vpc.id}"

   tags {
     Name = "wp_igw"
  }
}

#---routetablepublic-------

resource "aws_route_table" "wp_public_rt" {
   vpc_id = "${aws_vpc.wp_vpc.id}"
   
  route {
   cidr_block = "0.0.0.0/0"
   gateway_id = "${aws_internet_gateway.wp_internet_gateway.id}"
 } 


  tags {
   Name = "wp_public"
 }
}

#-----routetableprivate----

resource "aws_default_route_table" "wp_private_rt" {
  default_route_table_id = "${aws_vpc.wp_vpc.default_route_table_id}"

  tags {
   Name = "wp_private"
 }
}


#---------Subnets For Public1------------

resource "aws_subnet" "wp_public1_subnet" {
  vpc_id                  = "${aws_vpc.wp_vpc.id}"
  cidr_block              = "${var.cidrs["public1"]}"
  map_public_ip_on_launch = true
  availability_zone       = "${data.aws_availability_zones.available.names[0]}"

  tags {
    Name = "wp_public1"
  }
}

#----Subnet for Private1------

resource "aws_subnet" "wp_private1_subnet" {
  vpc_id                  = "${aws_vpc.wp_vpc.id}"
  cidr_block              = "${var.cidrs["private1"]}"
  map_public_ip_on_launch = false
  availability_zone       = "${data.aws_availability_zones.available.names[1]}"

  tags {
    Name = "wp_private1"
  }
}


#-----Now lets do Subnet Associations with there route tables 1public and 1private----------

resource "aws_route_table_association" "wp_public1_assoc" {
  subnet_id      = "${aws_subnet.wp_public1_subnet.id}"
  route_table_id = "${aws_route_table.wp_public_rt.id}"
}

resource "aws_route_table_association" "wp_private1_assoc" {
  subnet_id      = "${aws_subnet.wp_private1_subnet.id}"
  route_table_id = "${aws_default_route_table.wp_private_rt.id}"
}


#------security groups for web_server-----


resource "aws_security_group" "wp_dev_sg" {
  name        = "wp_dev_sg"
  description = "Used for access to the dev instance"
  vpc_id      = "${aws_vpc.wp_vpc.id}"

  #SSH

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  #HTTP

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#---Public Security Group this will provide access to Elastic Load Balancer-----

resource "aws_security_group" "wp_public_sg" {
  name        = "wp_public_sg"
  description = "Used for the elactic load balancer for public access"
  vpc_id      = "${aws_vpc.wp_vpc.id}"

  #HTTP 

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  #Outbound internet access

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
 }
}

#---Private Security Group------

resource "aws_security_group" "wp_private_sg" {
  name        = "wp_private_sg"
  description = "Used for private instances"
  vpc_id      = "${aws_vpc.wp_vpc.id}"

  # Access from VPC

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${var.vpc_cidr}"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
 }
}

#-------Key-Pair is the ssh-keygen----------


resource "aws_key_pair" "hello" {
  key_name   = "${var.key_name}"
  public_key = "${file(var.public_key_path)}"
}

#-------Ec2 Instance creation------
resource "aws_instance" "web" {
  ami                    = "${var.dev_ami}"
  count                  = "${var.count}"
#  key_name               = "${var.key_name}"
  key_name               = "${aws_key_pair.hello.id}"
  vpc_security_group_ids = ["${aws_security_group.wp_dev_sg.id}"]
  subnet_id              = "${aws_subnet.wp_public1_subnet.id}"
  source_dest_check = false
  instance_type = "t2.micro"

tags {
    Name = "web"
  }
}

#-------Elasctic load Balancer------

resource "aws_elb" "wp_elb" {
  name = "elb"

  subnets = ["${aws_subnet.wp_public1_subnet.id}"
  ]

  security_groups = ["${aws_security_group.wp_public_sg.id}"]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = "${var.elb_healthy_threshold}"
    unhealthy_threshold = "${var.elb_unhealthy_threshold}"
    timeout             = "${var.elb_timeout}"
    target              = "TCP:80"
    interval            = "${var.elb_interval}"
  }

  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

}

#----userdata
#     provisioner "local-exec" {
 #      command = <<EOT
#cat <<EOF > userdata
#!/bin/bash
#echo "Hello, World" > index.html
#nohup busybox httpd -f -p 8080 &
#EOF
#EOT
 # }
#}  

#---------launch configuration-------------

resource "aws_launch_configuration" "wp_lc" {
  name_prefix          = "wp_lc"
  image_id             = "${var.dev_ami}"
  instance_type        = "t2.micro"
  security_groups      = ["${aws_security_group.wp_private_sg.id}"]
  key_name             = "${aws_key_pair.wp_auth.id}"
  user_data            = "${file("userdata")}"

  lifecycle {
    create_before_destroy = true
  }
}


------Autoscalling---ASG--------

resource "aws_autoscaling_group" "wp_asg" {
  name                      = "asg-${aws_launch_configuration.wp_lc.id}"
  max_size                  = "${var.asg_max}"
  min_size                  = "${var.asg_min}"
  health_check_grace_period = "${var.asg_grace}"
  health_check_type         = "${var.asg_hct}"
  desired_capacity          = "${var.asg_cap}"
  force_delete              = true
  load_balancers            = ["${aws_elb.wp_elb.id}"]

  vpc_zone_identifier = ["${aws_subnet.wp_private1_subnet.id}"
  ]

  launch_configuration = "${aws_launch_configuration.wp_lc.name}"

  tag {
    key                 = "Name"
    value               = "wp_asg-instance"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}


