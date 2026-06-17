terraform {
    required_providers {
        yandex = {
            source  = "yandex-cloud/yandex"
            version = "0.209.0"
        }
    }
    required_version = ">=1.8.4"
}

provider "yandex" {
    cloud_id                 = "b1g9fi7ubfusdfsbbq0a"
    folder_id               = "b1g3u6tpspnd7qvsmqhf"
    service_account_key_file = "/home/vboxuser/.authorized_key.json"
    zone                    = "ru-central1-b"
}

resource "yandex_vpc_network" "network1" {
    name = "network1"
}

resource "yandex_vpc_subnet" "subnet1" {
    name           = "subnet1"
    zone           = "ru-central1-b"
    network_id     = yandex_vpc_network.network1.id
    v4_cidr_blocks = ["172.24.0.0/24"]
}

resource "yandex_compute_instance" "vm" {
    count = 2

    name        = "vm${count.index}"
    platform_id = "standard-v1"

    depends_on = [yandex_vpc_network.network1, yandex_vpc_subnet.subnet1]

    boot_disk {
        initialize_params {
            image_id = "fd8tm4ja1he7v7vknauu"
            size     = 10
        }
    }

    network_interface {
        subnet_id = yandex_vpc_subnet.subnet1.id
        nat       = true
    }

    resources {
        cores  = 2
        memory = 2
    }

    metadata = {
        ssh-keys = "ubuntu:${file("~/.ssh/new_terraform_key.pub")}"
    }
}

resource "yandex_lb_target_group" "group1" {
    name = "group1"

    depends_on = [yandex_compute_instance.vm]

    dynamic "target" {
        for_each = yandex_compute_instance.vm
        content {
            subnet_id = yandex_vpc_subnet.subnet1.id
            address   = try(target.value.network_interface[0].ip_address, "N/A")
        }
    }
}

resource "yandex_lb_network_load_balancer" "balancer1" {
    name = "balancer1"
    deletion_protection = false

    depends_on = [yandex_lb_target_group.group1]

    listener {
        name = "my-lb1"
        port = 80
        external_address_spec {
            ip_version = "ipv4"
        }
    }

    attached_target_group {
        target_group_id = try(yandex_lb_target_group.group1.id, "N/A")

        healthcheck {
            name = "http"
            http_options {
                port = 80
                path = "/"
            }
        }
    }
}