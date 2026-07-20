# Ballerina Azure Files connector

This repository contains the source code for the Ballerina Azure Files connector (`ballerinax/azure.storage.files`) — a connector for [Azure Files](https://learn.microsoft.com/en-us/azure/storage/files/storage-files-introduction), backed by the official [`azure-storage-file-share`](https://learn.microsoft.com/en-us/java/api/overview/azure/storage-file-share-readme) Java SDK.

It provides:

- **`Client`** — a share-scoped client for the directories and files within a single share.
- **`AdminClient`** — an account-level client for managing shares.

> **Status: client surface implemented.** All `Client` and `AdminClient` operations are implemented over the Azure SDK and covered by tests: the core share, directory, file, transfer, copy, and range operations, plus snapshots, leases, property setters, access policies, SDDL permissions, SMB handles, SAS generation, NFS links, and service properties. Authentication covers shared key, SAS, connection strings, and Microsoft Entra ID, with configurable retry, proxy, connection-pool, and TLS transport settings. A polling listener for reacting to files as they appear is planned for a later release.

## Building from the source

### Prerequisites

- [Ballerina Swan Lake](https://ballerina.io/downloads/) 2201.12.0 or later, for building and testing directly.
- OpenJDK 21, for building the `native/` adaptor module.
- Docker, only for the Gradle build. The Gradle plugin builds connector packages inside the `ballerina/ballerina` image, so the Docker daemon must be running for `./gradlew build`. Day-to-day development does not need it.

### Build the package

Everyday development uses the Ballerina CLI directly:

```sh
./gradlew :azure.storage.files-native:build   # build the Java adaptor jar (needed once, and after native/ changes)
bal build ./ballerina                          # compile the package
bal test --groups mock ./ballerina             # run the credential-free test suite
```

The full Gradle build compiles the Java adaptor, then builds and tests the Ballerina package inside a Docker container (this is how CI builds the repository):

```sh
./gradlew clean build
```

## Testing

The test suite has two groups; see [`ballerina/tests/README.md`](ballerina/tests/README.md) for the full guide.

- **`mock`** runs against an in-process mock of the Azure Files REST service. It needs no credentials and no network, and runs on every build.
- **`live`** runs smoke tests against a real Azure storage account. It is disabled unless credentials are supplied in `ballerina/tests/Config.toml`, so it never runs accidentally (on CI or forks it simply skips).

## Contributing

As an open-source project, Ballerina welcomes contributions from the community. For more information, see [the contribution guidelines](https://github.com/ballerina-platform/ballerina-lang/blob/master/CONTRIBUTING.md).

## Useful links

- Chat live with us via our [Discord server](https://discord.gg/ballerinalang).
- Post technical questions on Stack Overflow with the [#ballerina](https://stackoverflow.com/questions/tagged/ballerina) tag.
