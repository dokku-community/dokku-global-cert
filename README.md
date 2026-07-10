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
global-cert:apply <app>...  # Applies the global certificate to one or more existing apps, overwriting any certificate they already have
global-cert:generate        # Generate a key and certificate signing request (and self-signed certificate)
global-cert:remove          # Remove the SSL configuration
global-cert:report [<app>|--global] [<flag>] # Displays a global-cert report for one or more apps
global-cert:set [--force] CRT KEY # Sets a global ssl endpoint. Can also import from a tarball on stdin
```

## usage

While Dokku supports per-application SSL certificates, it does not natively provide global certificate setting. This plugin allows setting a global certificate, which is imported for all new applications and applied to every existing application that does not already have its own certificate. Updating the global certificate also re-applies it to every application that currently uses it, so renewals (for example a rotated wildcard certificate) propagate to existing applications and are served immediately. Applications that have been given their own certificate are left untouched unless `--force` is passed. The interface is similar to that of the official `certs` plugin, though with minor changes to reflect it's usage.

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

Setting the global certificate applies it to every existing application that does not already have its own certificate, so applications created before the global certificate was set start serving it immediately. Re-running `global-cert:set` is therefore also the way to apply the certificate to applications on an existing install.

To re-apply the global certificate to every application - including applications that were given their own certificate - pass `--force`:

```shell
dokku global-cert:set --force server.crt server.key
```

The `--force` flag also works as a global flag:

```shell
dokku --force global-cert:set server.crt server.key
```

### applying the global certificate to an existing app

The `global-cert:apply` command applies the currently stored global certificate to one or more existing applications, overwriting whatever certificate each application already has. It reuses the certificate already set with `global-cert:set`, so no certificate files are needed:

```shell
dokku global-cert:apply node-js-app
```

Multiple applications can be given in a single invocation:

```shell
dokku global-cert:apply node-js-app python-app
```

Unlike `global-cert:set`, which leaves applications with their own certificate untouched, `global-cert:apply` always overwrites the certificate on the named applications. This is the way to switch an application that was given its own certificate - for example one issued by `dokku-letsencrypt` - back to the global certificate. A global certificate must be set first; applying to an application that does not exist, or when no global certificate is set, fails.

### certificate removal

The global certificate can be removed with the following command:

```shell
dokku global-cert:remove
```

If the global certificate is removed, existing applications will continue to have the global certificate set.

### reporting

The `global-cert:report` command displays the global certificate status. With no arguments it prints one block per application, each showing whether that application currently serves the global certificate (`--global-cert-applied`) alongside the global certificate's properties:

```shell
dokku global-cert:report
dokku global-cert:report node-js-app
```

An application serves the global certificate when its certificate matches the one stored by `global-cert:set`; an application given its own certificate reports `--global-cert-applied` as `false`.

Pass `--global` to report on the global certificate itself instead of an application:

```shell
dokku global-cert:report --global
```

A single value can be fetched by passing the corresponding flag, which is useful for scripting:

```shell
dokku global-cert:report node-js-app --global-cert-applied
dokku global-cert:report --global --global-cert-enabled
```

The report can also be emitted as JSON with `--format json`, in which case the keys are the flag names with the leading `--global-cert-` stripped. The `--format` flag cannot be combined with a single info flag:

```shell
dokku global-cert:report --global --format json
```
