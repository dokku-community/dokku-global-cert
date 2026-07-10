# dokku-global-cert [![ci](https://github.com/dokku-community/dokku-global-cert/actions/workflows/ci.yml/badge.svg)](https://github.com/dokku-community/dokku-global-cert/actions/workflows/ci.yml)

Manages a global certificate for dokku.

## requirements

- dokku 0.7.0+
- docker 1.12.x

## installation

```shell
dokku plugin:install https://github.com/josegonzalez/dokku-global-cert.git global-cert
```

## commands

```shell
global-cert:generate        # Generate a key and certificate signing request (and self-signed certificate)
global-cert:remove          # Remove the SSL configuration
global-cert:report [<flag>] # Displays a global ssl report
global-cert:set CRT KEY     # Sets a global ssl endpoint. Can also import from a tarball on stdin
```

## usage

While Dokku supports per-application SSL certificates, it does not natively provide global certificate setting. This plugin allows setting a global certificate, which will then be imported for all new applications. The interface is similar to that of the official `certs` plugin, though with minor changes to reflect it's usage.

### certificate setting

The `global-cert:set` command can be used to push a `tar` containing a certificate `.crt` and `.key` file to a single application. The command should correctly handle cases where the `.crt` and `.key` are not named properly or are nested in a subdirectory of said `tar` file. You can import it as follows:

```shell
# if your `.crt` file came alongside a `.ca-bundle`, you'll want to 
# concatenate those into a single `.crt` file before adding it to the `.tar`.
cat yourdomain_com.crt yourdomain_com.ca-bundle > server.crt

# tar the certificates
tar cvf cert-key.tar server.crt server.key
dokku global-cert:set < cert-key.tar
```

You can also import certs without using `stdin`, and instead specifying a full path on disk:

```shell
dokku global-cert:set server.crt server.key
```

### certificate removal

The global certificate can be removed with the following command:

```shell
dokku global-cert:remove
```

If the global certificate is removed, existing applications will continue to have the global certificate set.
