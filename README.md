# Ballerina Azure Files connector

This repository contains the source code for the Ballerina Azure Files connector (`ballerinax/azure.storage.files`) — a connector for [Azure Files](https://learn.microsoft.com/en-us/azure/storage/files/storage-files-introduction), backed by the official [`azure-storage-file-share`](https://learn.microsoft.com/en-us/java/api/overview/azure/storage-file-share-readme) Java SDK.

It provides:

- **`Client`** — a share-scoped client for the directories and files within a single share.
- **`AdminClient`** — an account-level client for managing shares.
- **`Listener`** — a polling listener that dispatches an `onFile` event for each file present in the watched path (consume-style), with a `Caller` for acting on the file. Snapshot-diff events (`onFileAdd`/`onFileDelete`/`onFileModify`) are planned post-v0.1.

> **Status: API skeleton.** The `ballerina/` package currently holds the first-release (v0.1) API surface with stubbed operation bodies, published for design review ahead of implementation. Operations return a `NotImplemented` error until they are implemented.

## Building from the source

### Prerequisites

- [Ballerina Swan Lake](https://ballerina.io/downloads/) (2201.12.0 or later)

### Build the package

```sh
bal build ./ballerina
```

To produce a BALA:

```sh
bal pack ./ballerina
```

## Contributing

As an open-source project, Ballerina welcomes contributions from the community. For more information, see [the contribution guidelines](https://github.com/ballerina-platform/ballerina-lang/blob/master/CONTRIBUTING.md).

## Useful links

- Chat live with us via our [Discord server](https://discord.gg/ballerinalang).
- Post technical questions on Stack Overflow with the [#ballerina](https://stackoverflow.com/questions/tagged/ballerina) tag.
