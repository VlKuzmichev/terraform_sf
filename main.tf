terraform {
required_version = "= 1.1.3"
  required_providers { 
    yandex = {
      source = "yandex-cloud/yandex"
      version = "~> 0.61.0"
    }
  }
  
#Используем удаленное хранилище state
  backend "s3" {
    endpoint   = "storage.yandexcloud.net"
    bucket     = "tf-state-bucket-vk"
    region     = "ru-central1-a"
    key        = "issue1/lemp.tfstate"
    access_key = "deleted"
    secret_key = "deleted"
 
    skip_region_validation      = true
    skip_credentials_validation = true
  }
}

#Провайдер
provider "yandex" {
  token     = "deleted"
  cloud_id  = "b1gbte3pjhdad43jg0al"
  folder_id = var.folder_id
}

#Создаем таргет группу для подсети 1 и инстанса 1 
resource "yandex_lb_target_group" "tg-group1" {
  name = "tg-group1"
  region_id = "ru-central1"
  
  target {
   subnet_id = yandex_vpc_subnet.subnet1.id 
   address   = module.ya_instance_1.internal_ip_address_vm
  }
}

#Создаем таргет группу для подсети 2 и инстанса 2 
resource "yandex_lb_target_group" "tg-group2" {
  name = "tg-group2"

  target {
    subnet_id = yandex_vpc_subnet.subnet2.id
    address   = module.ya_instance_2.internal_ip_address_vm
  }
}

# Создаем лоадбалансер
resource "yandex_lb_network_load_balancer" "vk-balancer" {
  name = "my-network-load-balancer"

# Добавляем слушатель на 80 порт
  listener {
    name = "my-listener"
    port = 80
    external_address_spec {
      ip_version = "ipv4"
    }
  }

# Добавляем таргет группу 1
  attached_target_group {
    target_group_id = yandex_lb_target_group.tg-group1.id

    healthcheck {
      name = "http"
      http_options {
        port = 80
        path = "/"
      }
    }
  }

# Добавляем таргет группу 2
  attached_target_group {
    target_group_id = yandex_lb_target_group.tg-group2.id

    healthcheck {
      name = "http"
      http_options {
        port = 80
        path = "/"
      }
    }
  }

}

#Создаем сеть
resource "yandex_vpc_network" "network" {
  name = "network"
}

#Подсеть 1
resource "yandex_vpc_subnet" "subnet1" {
  name           = "subnet1"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = ["192.168.10.0/24"]
}

#Подсеть 2
resource "yandex_vpc_subnet" "subnet2" {
  name           = "subnet2"
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = ["192.168.11.0/24"]
}

#Инстанс 1 на образе LEMP
module "ya_instance_1" {
  source                = "./modules/instance"
  instance_family_image = "lemp"
  vpc_subnet_id         = yandex_vpc_subnet.subnet1.id
  zone                  = yandex_vpc_subnet.subnet1.zone
}

#Инстанс 2 на образе LAMP
module "ya_instance_2" {
  source                = "./modules/instance"
  instance_family_image = "lamp"
  vpc_subnet_id         = yandex_vpc_subnet.subnet2.id
  zone                  = yandex_vpc_subnet.subnet2.zone
}

# Создаем сервис-аккаунт SA
resource "yandex_iam_service_account" "sa" {
  folder_id = var.backet_folder_id
  name      = "sa-my"
}

# Даем права на запись для этого SA
resource "yandex_resourcemanager_folder_iam_member" "sa-editor" {
  folder_id = var.backet_folder_id
  role      = "storage.editor"
  member    = "serviceAccount:${yandex_iam_service_account.sa.id}"
}

# Создаем ключи доступа Static Access Keys
resource "yandex_iam_service_account_static_access_key" "sa-static-key" {
  service_account_id = yandex_iam_service_account.sa.id
  description        = "static access key for object storage"
}

# Создаем хранилище
resource "yandex_storage_bucket" "state" {
  bucket     = "tf-state-bucket-vk"
  access_key = yandex_iam_service_account_static_access_key.sa-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
}

