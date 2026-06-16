# SSL Initialization for Windows (PowerShell)
$domains = "moyeolog.kro.kr"
$data_path = "./data/certbot"
$email = "ruraeru@gmail.com"
$staging = 0 # Set to 1 for testing

if (!(Test-Path "$data_path/conf/options-ssl-nginx.conf")) {
    New-Item -ItemType Directory -Force -Path "$data_path/conf"
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf" -OutFile "$data_path/conf/options-ssl-nginx.conf"
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem" -OutFile "$data_path/conf/ssl-dhparams.pem"
}

Write-Host "### Creating dummy certificate for $domains ..."
$cert_path = "/etc/letsencrypt/live/$domains"
New-Item -ItemType Directory -Force -Path "$data_path/conf/live/$domains"

docker compose run --rm --entrypoint "openssl req -x509 -nodes -newkey rsa:1024 -days 1 -keyout '$cert_path/privkey.pem' -out '$cert_path/fullchain.pem' -subj '/CN=localhost'" certbot

Write-Host "### Starting nginx ..."
docker compose up --force-recreate -d nginx

Write-Host "### Deleting dummy certificate for $domains ..."
docker compose run --rm --entrypoint "rm -rf /etc/letsencrypt/live/$domains /etc/letsencrypt/archive/$domains /etc/letsencrypt/renewal/$domains.conf" certbot

Write-Host "### Requesting real certificate for $domains ..."
$email_arg = if ($email) { "--email $email" } else { "--register-unsafely-without-email" }
$staging_arg = if ($staging -eq 1) { "--staging" } else { "" }

docker compose run --rm --entrypoint "certbot certonly --webroot -w /var/www/certbot $staging_arg $email_arg -d $domains --rsa-key-size 4096 --agree-tos --force-renewal" certbot

Write-Host "### Reloading nginx ..."
docker compose exec nginx nginx -s reload
