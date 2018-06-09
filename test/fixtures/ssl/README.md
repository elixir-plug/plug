How to generate keys for use with tests

# Generate Certificate Authority Certificates

- `openssl genrsa -out ca-key.pem 1024`
- `openssl req -new -x509 -sha256 -days 730 -key ca-key.pem -out ca.pem`
  - Set CN to `Elixir CA`
  - Set password to `cowboy`

# Generate Server Certificates

- `openssl genrsa -out server-key.pem 1024`
- `openssl req -new -key server-key.pem -sha256 -out server.csr`
  - Set CN to `localhost`
- `openssl x509 -req -days 365 -sha256 -in server.csr -CA ca.pem -CAkey ca-key.pem -set_serial 1 -out server.pem`
- `openssl rsa -des -in server.key -out server.key.enc`
  - Set password to `cowboy`

# Generate Client Certificates

- `openssl genrsa -out client-key.pem 1024`
- `openssl req -new -key client-key.pem -out client.csr`
  - Set CN to `client`
- `openssl x509 -req -days 3650 -sha256 -in client.csr -CA ca.pem -CAkey ca-key.pem -set_serial 2 -out client.pem`
