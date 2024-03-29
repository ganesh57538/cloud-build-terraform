provider "google"{
	#credentials=file(var.credentials)
	project=var.projectName
	region=var.regionName
  	zone=var.zoneName
}

resource "google_compute_network" "test-vpc"{
	name="test-vpc"
	auto_create_subnetworks="false"
}

resource "google_compute_subnetwork" "test-subnet"{
	name="test-subnet"
	network=google_compute_network.test-vpc.name
	ip_cidr_range="10.0.0.0/24"
}

resource "google_compute_firewall" "test-vpc-http"{
	name="test-vpc-http"
	network=google_compute_network.test-vpc.name
	allow{
		protocol="tcp"
		ports=[80,443,22]
	}
	target_tags=["apache-server"]
}

resource "google_compute_instance" "apache"{
	name="apache-server"
	machine_type="f1-micro"
	boot_disk{
		initialize_params{
			image="ubuntu-1804-lts"
		}
	}
	network_interface{
		network=google_compute_network.test-vpc.name
		subnetwork=google_compute_subnetwork.test-subnet.name
		access_config{

		}
	}
	tags=["apache-server"]
	metadata_startup_script="sudo apt-get update;sudo apt-get install apache2 -y;sudo systemctl start apache2"
}

resource "google_compute_firewall" "test-vpc-ssh"{
	name="test-vpc-ssh"
	network=google_compute_network.test-vpc.name
	allow{
		protocol="tcp"
		ports=[22]
	}
	target_tags=["proxy-server"]
}

resource "google_compute_instance" "proxy-server"{
	name="proxy-server"
	machine_type="f1-micro"
	boot_disk{
		initialize_params{
			image="ubuntu-1804-lts"
		}
	}
	network_interface{
		network=google_compute_network.test-vpc.name
		subnetwork=google_compute_subnetwork.test-subnet.name
	}
 	metadata_startup_script="sudo apt-get install postgresql-client -y"
	tags=["proxy-server"]
}

resource "google_compute_global_address" "private_ip_address" {

  name          = "private-ip-address"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.test-vpc.self_link
}

resource "google_service_networking_connection" "private_vpc_connection" {

  network                 = google_compute_network.test-vpc.self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

resource "random_id" "db_name_suffix" {
  byte_length = 4
}

resource "google_sql_database_instance" "db-instance" {

  name   = "private-instance-${random_id.db_name_suffix.hex}"
  region=var.regionName
  database_version = "POSTGRES_9_6"
  depends_on = [google_service_networking_connection.private_vpc_connection]

  settings {
    tier = "db-f1-micro"
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.test-vpc.self_link
    }
  }
}

resource "google_compute_router" "nat-router"{
	name="nat-router"
	region=var.regionName
	network=google_compute_network.test-vpc.self_link
	bgp{
		asn=65000
	}
}

resource "google_compute_router_nat" "test-nat"{
	name="test-nat"
	region=var.regionName
	router=google_compute_router.nat-router.name
	nat_ip_allocate_option="AUTO_ONLY"
	source_subnetwork_ip_ranges_to_nat="ALL_SUBNETWORKS_ALL_IP_RANGES"
}



