# HTTPS

Plug can serve HTTP over TLS ('HTTPS') through an appropriately configured Adapter. While the exact syntax for defining an HTTPS listener is adapter-specific, Plug does define a common set of TLS configuration options that most adapters support, formally documented as `Plug.SSL.configure/1`.

This guide describes how to use these parameters to set up an HTTPS server with Plug, and documents some best-practices and potential pitfalls.

> Editor's note: The secure transport protocol used by HTTPS is nowadays referred to as TLS. However, the application in the Erlang/OTP standard library that implements it is called `:ssl`, for historical reasons. In this document we will refer to the protocol as 'TLS' and to the Erlang/OTP implementation as `:ssl`, and its configuration parameters as `:ssl` options.

## Prerequisites

The prerequisites for running an HTTPS server with Plug include:

* The Erlang/OTP runtime, with OpenSSL bindings; run `:crypto.info_lib()` in an IEx session to verify
* A Plug Adapter that supports HTTPS, e.g. [Plug.Cowboy](https://hex.pm/packages/plug_cowboy)
* A valid certificate and associated private key

### Self-signed Certificate

For testing purposes it may be sufficient to use a self-signed certificate. Such certificates generally result in warnings in browsers and failed connections from other tools, but these can be overridden to enable HTTPS testing. This is especially useful for local testing of HTTP 2, which is only specified over TLS.

> **Warning**: use self-signed certificates only for local testing, and do not mark such test certificates as globally trusted in browsers or operating system!

The [Phoenix](https://phoenixframework.org/) project includes a Mix task `mix phx.gen.cert` that generates the necessary files and places them in the application's 'priv' directory. The [X509](https://hex.pm/packages/x509) package can be used as a dev-only dependency to add a similar `mix x509.gen.selfsigned` task to non-Phoenix projects.

Alternatively, the OpenSSL CLI or other utilities can be used to generate a self-signed certificate. Instructions are widely available online.

### CA Issued Certificate

For staging and production it is necessary to obtain a CA-signed certificate from a trusted Certificate Authority, such as [Let's Encrypt](https://letsencrypt.org). Certificates issued by a CA usually come with an additional file containing one or more certificates that make up the 'CA chain'.

For use with Plug the certificates and key should be stored in PEM format, containing Base64-encoded data between 'BEGIN' and 'END' markers. Some useful OpenSSL commands for converting certificates/keys from other formats can be found at [the end of this document](#converting-certificates-and-keys).

## Getting Started

A minimal HTTPS listener, using Plug.Cowboy, might be defined as follows:

```elixir
Plug.Cowboy.https MyApp.MyPlug, [],
  port: 8443,
  cipher_suite: :strong,
  certfile: "/etc/letsencrypt/live/example.net/cert.pem",
  keyfile: "/etc/letsencrypt/live/example.net/privkey.pem",
  cacertfile: "/etc/letsencrypt/live/example.net/chain.pem"
```

The `cacertfile` option is not needed when using a self-signed certificate, or when the file pointed to by `certfile` contains both the server certificate and all necessary CA chain certificates:

```elixir
  #...
  certfile: "/etc/letsencrypt/live/example.net/fullchain.pem",
  keyfile: "/etc/letsencrypt/live/example.net/privkey.pem"
```

It is possible to bundle the certificate files with the application, possibly for packaging into a release. In this case the files must be stored under the application's 'priv' directory. The `otp_app` option must be set to the name of the OTP application that contains the files, in order to correctly resolve the relative paths:

```elixir
Plug.Cowboy.https MyApp.MyPlug, [],
  port: 8443,
  cipher_suite: :strong,
  certfile: "priv/cert/selfsigned.pem",
  keyfile: "priv/cert/selfsigned_key.pem",
  otp_app: :my_app
```

Remember to exclude the files from version control, unless the certificate and key are shared by all developers for testing purposes only. For example, add this line to the '.gitignore' file: `priv/**/*.pem`.

## TLS Protocol Options

In addition to a certificate, an HTTPS server needs a secure TLS protocol configuration. `Plug.SSL` always sets the following options:

* Set `secure_renegotiate: true`, to avoid certain types of man-in-the-middle attacks
* Set `reuse_sessions: true`, for improved handshake performance of recurring connections

Additional options can be set by selecting a predefined profile or by setting `:ssl` options individually.

### Predefined Options

To simplify configuration of TLS defaults Plug provides two preconfigured options: `cipher_suite: :strong` and `cipher_suite: :compatible`.

The `:strong` profile enables AES-GCM ciphers with ECDHE or DHE key exchange, and TLS version 1.2 only. It is intended for typical installations with support for browsers and other modern clients.

The `:compatible` profile additionally enables AES-CBC ciphers, as well as TLS versions 1.1 and 1.0. Use this configuration to allow connections from older clients, such as older PC or mobile operating systems. Note that RSA key exchange is not enabled by this configuration, due to known weaknesses, so to support clients that do not support ECDHE or DHE it is necessary specify the ciphers explicitly (see [below](#manual-configuration)).

In addition, both profiles:

* Configure the server to choose a cipher based on its own preferences rather than the client's (`honor_cipher_order` set to `true`); when specifying a custom cipher list, ensure the ciphers are listed in descending order of preference
* Select the 'Prime' (SECP) curves for use in Elliptic Curve Cryptography (ECC)

All these parameters, including the global defaults mentioned above, can be overridden by specifying custom `:ssl` configuration options.

It is worth noting that the cipher lists and TLS protocol versions selected by the profiles are whitelists. If a new Erlang/OTP release introduces new TLS protocol versions or ciphers that are not included in the profile definition, they would have to be enabled explicitly by overriding the `:ciphers` and/or `:versions` options, until such time as they are added to the `Plug.SSL` profiles.

The ciphers chosen and related configuration are based on [OWASP recommendations](https://www.owasp.org/index.php/TLS_Cipher_String_Cheat_Sheet), with some modifications as described in the `Plug.SSL.configure/1` documentation.

### Manual Configuration

Please refer to the [Erlang/OTP `:ssl` documentation](http://erlang.org/doc/man/ssl.html) for details on the supported configuration options.

An example configuration with custom `:ssl` options might look like this:

```elixir
Plug.Cowboy.https MyApp.MyPlug, [],
  port: 8443,
  certfile: "/etc/letsencrypt/live/example.net/cert.pem",
  keyfile: "/etc/letsencrypt/live/example.net/privkey.pem",
  cacertfile: "/etc/letsencrypt/live/example.net/chain.pem",
  versions: [:"tlsv1.2", :"tlsv1.1"],
  ciphers: [
    'ECDHE-RSA-AES256-GCM-SHA384',
    'ECDHE-RSA-AES128-GCM-SHA256',
    'DHE-RSA-AES256-GCM-SHA384',
    'DHE-RSA-AES128-GCM-SHA256'
  ],
  honor_cipher_order: true,
  sni_fun: &MyPlug.ssl_opts_for_hostname/1
```

## HTTP Strict Transport Security (HSTS)

Once a server is configured to support HTTPS it is often a good idea to redirect HTTP requests to HTTPS. To do this, include `Plug.SSL` in the Plug pipeline.

To prevent downgrade attacks, in which an attacker intercepts a plain HTTP request to the server before the redirect to HTTPS takes place, `Plug.SSL` by default sets the '[Strict-Transport-Security](https://www.owasp.org/index.php/HTTP_Strict_Transport_Security_Cheat_Sheet)' (HSTS) header. This informs the browser that the current site must only ever be accessed over HTTPS, even if the user typed or clicked a plain HTTP URL. This only works if the site is reachable on port 443 (see [Listening on Port 443](#listening-on-port-443), below).

> **Warning**: it is very difficult, if not impossible, to revert the effect of HSTS before the entry stored in the browser expires! Consider using a short `:expires` value initially, and increasing it to a large value (e.g. 31536000 seconds for 1 year) after testing.

The Strict-Transport-Security header can be disabled altogether by setting `hsts: false` in the `Plug.SSL` options.

## Encrypted Keys

To protect the private key on disk it is best stored in encrypted PEM format, protected by a password. When configuring a Plug server with an encrypted private key, specify the password using the `:password` option:

```elixir
Plug.Cowboy.https MyApp.MyPlug, [],
  port: 8443,
  certfile: "/etc/letsencrypt/live/example.net/cert.pem",
  keyfile: "/etc/letsencrypt/live/example.net/privkey_aes.pem",
  cacertfile: "/etc/letsencrypt/live/example.net/chain.pem",
  password: "SECRET"
```

To encrypt an existing PEM-encoded RSA key use the OpenSSL CLI: `openssl rsa -in privkey.pem -out privkey_aes.pem -aes128`. Use `ec` instead of `rsa` when using an ECDSA certificate. Don't forget to securely erase the unencrypted copy afterwards! Best practice would be to encrypt the file immediately during initial key generation: please refer to the instructions provided by the CA.

> Note: at the time of writing, Erlang/OTP does not support keys encrypted with AES-256. The OpenSSL command in the previous paragraph can also be used to convert an AES-256 encrypted key to AES-128.

## Passing DER Binaries

Sometimes it is preferable to not store the private key on disk at all. Instead, the private key might be passed to the application using an environment variable or retrieved from a key store such as Vault.

In such cases it is possible to pass the private key directly, using the `:key` parameter. For example, assuming an RSA private key is available in the PRIVKEY environment variable in Base64 encoded DER format, the key may be set as follows:

```elixir
der = System.get_env("PRIVKEY") |> Base.decode64!
Plug.Cowboy.https MyApp.MyPlug, [],
  port: 8443,
  key: {:RSAPrivateKey, der},
  #....
```

Note that reading environment variables in Mix config files only works when starting the application using Mix, e.g. in a development environment. In production, a different approach is needed for runtime configuration, but this is out of scope for the current document.

The certificate and CA chain can also be specified using DER binaries, using the `:cert` and `:cacerts` options, but this is best avoided. The use of PEM files has been tested much more thoroughly with the Erlang/OTP `:ssl` application, and there have been a number of issues with DER binary certificates in the past.

## Custom Diffie-Hellman Parameters

It is recommended to generate a custom set of Diffie-Hellman parameters, to be used for the DHE key exchange. Use the following OpenSSL CLI command to create a `dhparam.pem` file:

`openssl dhparam -out dhparams.pem 4096`

On a slow machine (e.g. a cheap VPS) this may take several hours. You may want to run the command on a strong machine and copy the file over to the target server: the file does not need to be kept secret. It is best practice to rotate the file periodically.

Pass the (relative or absolute) path using the `:dhfile` option:

```elixir
Plug.Cowboy.https MyApp.MyPlug, [],
  port: 8443,
  cipher_suite: :strong,
  certfile: "priv/cert/selfsigned.pem",
  keyfile: "priv/cert/selfsigned_key.pem",
  dhfile: "priv/cert/dhparams.pem",
  otp_app: :my_app
```

If no custom parameters are specified, Erlang's `:ssl` uses its built-in defaults. Since OTP 19 this has been the 2048-bit 'group 14' from RFC3526.

## Renewing Certificates

Whenever a certificate is about to expire, when the contents of the certificate have been updated, or when the certificate is 're-keyed', the HTTPS server needs to be updated with the new certificate and/or key.

When using the `:certfile` and `:keyfile` parameters to reference PEM files on disk, replacing the certificate and key is as simple as overwriting the files. Erlang's `:ssl` application periodically reloads any referenced files, with changes taking effect in subsequent handshakes. It may be best to use symbolic links that point to versioned copies of the files, to allow for quick rollback in case of problems.

Note that there is a potential race condition when both the certificate and the key need to be replaced at the same time: if the `:ssl` application reloads one file before the other file is updated, the partial update can leave the HTTPS server with a mismatched private key. This can be avoiding by placing the private key in the same PEM file as the certificate, and omitting the `:keyfile` option. This configuration allows atomic updates, and it works because `:ssl` looks for a private key entry in the `:certfile` PEM file if no `:key` or `:keyfile` option is specified.

While it is possible to update the DER binaries passed in the `:cert` or `:key` options (as well as any other TLS protocol parameters) at runtime, this requires knowledge of the internals of the Plug adapter being used, and is therefore beyond the scope of this document.

## Listening on Port 443

By default clients expect HTTPS servers to listen on port 443. It is possible to specify a different port in HTTPS URLs, but for public servers it is often preferable to stick to the default. In particular, HSTS requires that the site be reachable on port 443 using HTTPS.

This presents a problem, however: only privileged processes can bind to TCP port numbers under 1024, and it is bad idea to run the application as 'root'.

Leaving aside solutions that rely on external network elements, such as load balancers, there are several solutions on typical Linux servers:

* Deploy a reverse proxy or load balancer process, such as Nginx or HAProxy (see [Offloading TLS](#offloading-tls), below); the proxy listens on port 443 and passes the traffic to the Elixir application running on an unprivileged port
* Create an IPTables rule to forward packets arriving on port 443 to the port on which the Elixir application is running
* Give the Erlang/OTP runtime (that is, the BEAM VM executable) permission to bind to privileged ports using 'setcap', e.g. `sudo setcap 'cap_net_bind_service=+ep' /usr/lib/erlang/erts-10.1/bin/beam.smp`; update the path as necessary, and remember to run the command again after Erlang upgrades
* Use a tool such as 'authbind' to give an unprivileged user/group permission to bind to specific ports

This is not intended to be an exhaustive list, as this topic is actually a bit beyond the scope of the current document. The issue is a generic one, not specific to Erlang/Elixir, and further explanations can be found online.

## Offloading TLS

So far this document has focused on configuring Plug to handle TLS within the application. Some people instead prefer to terminate TLS in a proxy or load balancer deployed in front of the Plug application.

### Pros and Cons

Offloading might be done to achieve higher throughput, or to stick to the more widely used OpenSSL implementation of the TLS protocol. The Erlang/OTP implementation depends on OpenSSL for the underlying cryptography, but it implements its own message framing and protocol state machine. While it is not clear that one implementation is inherently more secure than the other, just patching OpenSSL along with everybody else in case of vulnerabilities might give peace of mind, compared to than having to research the implications on the Erlang/OTP implementation.

On the other hand, the proxy solution might not support end-to-end HTTP 2, limiting the benefits of the new protocol. It can also introduce operational complexities and new resource constraints, especially for long-lived connections such as WebSockets.

### Plug Configuration Impact

When using TLS offloading it may be necessary to make some configuration changes to the application.

`Plug.SSL` takes on another important role when using TLS offloading: it can update the `:scheme` and `:port` fields in the `Plug.Conn` struct based on an HTTP header (e.g. 'X-Forwarded-Proto'), to reflect the actual protocol used by the client (HTTP or HTTPS). It is very important that the `:scheme` field properly reflects the use of HTTPS, even if the connection between the proxy and the application uses plain HTTP, because cookies set by `Plug.Session` and `Plug.Conn.put_resp_cookie/4` by default set the 'secure' cookie flag only if `:scheme` is set to `:https`! When relying on this default behaviour it is essential that `Plug.SSL` is included in the Plug pipeline, that its `:rewrite_on` option is set correctly, and that the proxy sets the appropriate header.

The `:remote_ip` field in the `Plug.Conn` struct by default contains the network peer IP address. Terminating TLS in a separate process or network element typically masks the actual client IP address from the Elixir application. If proxying is done at the HTTP layer, the original client IP address is often inserted into an HTTP header, e.g. 'X-Forwarded-For'. There are Plugs available to extract the client IP from such a header, such as `Plug.RewriteOn`.

> **Warning**: ensure that clients cannot spoof their IP address by including this header in their original request, by filtering such headers in the proxy!

For solutions that operate below the HTTP layer, e.g. using HAProxy, the client IP address can sometimes be passed through the 'PROXY protocol'. Extracting this information must be handled by the Plug adapter. Please refer to the Plug adapter documentation for further information.

## Converting Certificates and Keys

When certificate and/or key files are not in provided in PEM format they can usually be converted using the OpenSSL CLI. This section describes some common formats and the associated OpenSSL commands to convert to PEM.

### From DER to PEM

DER-encoded files contain binary data. Common file extensions are `.crt` for certificates and `.key` for keys.

To convert a single DER-encoded certificate to PEM format: `openssl x509 -in server.crt -inform der -out cert.pem`

To convert an RSA private key from DER to PEM format: `openssl rsa -in privkey.der -inform der -out privkey.pem`. If the private key is a Elliptic Curve key, for use with an ECDSA certificate, replace `rsa` with `ec`. You may want to add the `-aes128` argument to produce an encrypted, password protected PEM file.

### From PKCS#12 to PEM

The PKCS#12 format is a container format containing one or more certificates and/or encrypted keys. Such files typically have a `.p12` extension.

To extract all certificates from a PKCS#12 file to a PEM file: `openssl pkcs12 -in server.p12 -nokeys -out fullchain.pem`. The resulting file contains all certificates from the input file, typically the server certificate and any CA certificates that make up the CA chain. You can split the file into separate `cert.pem` and `chain.pem` files using a text editor, or you can just pass `certfile: fullchain.pem` to the HTTPS adapter.

To extract a private key from a PKCS#12 file to a PEM file: `openssl pkcs12 -in server.p12 -nocerts -nodes -out privkey.pem`. You may want to replace the `-nodes` argument with `-aes128` to produce an encrypted, password protected PEM file.
