## Overview

[Azure Files](https://learn.microsoft.com/en-us/azure/storage/files/storage-files-introduction) offers fully managed file shares in the cloud, accessible via the industry-standard SMB and NFS protocols and a REST API.

This package provides a Ballerina connector for Azure Files, backed by the official [`azure-storage-file-share`](https://learn.microsoft.com/en-us/java/api/overview/azure/storage-file-share-readme) Java SDK. It exposes:

- **`Client`** — a share-scoped client for working with the directories and files in a single share (create, upload, download, copy, rename, ranges, and more).
- **`AdminClient`** — an account-level client for managing shares (create, list, delete, restore).
- **`Listener`** — a polling listener that watches a share and dispatches `onFileAdd`, `onFileDelete`, and `onFileModify` events to a service, with a `Caller` for acting on the file that triggered each event.

> **Status: API skeleton.** This is the first-release (v0.1) API surface with stubbed operation bodies, published for design review ahead of implementation. Operations currently return a `NotImplemented` error.

## Quickstart

```ballerina
import ballerinax/azure.storage.files;

files:Client fileClient = check new (
    {accountName: "<account>", auth: {accountKey: "<key>"}},
    "<share-name>"
);

files:Properties props = check fileClient->getProperties("reports/q1.pdf");
```

## Report issues

To report bugs, request new features, start discussions, or ask questions, open an issue in the [Ballerina library repository](https://github.com/ballerina-platform/ballerina-library/issues).

## Useful links

- Chat live with us via our [Discord server](https://discord.gg/ballerinalang).
- Post technical questions on Stack Overflow with the [#ballerina](https://stackoverflow.com/questions/tagged/ballerina) tag.
