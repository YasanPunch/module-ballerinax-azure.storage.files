[Azure Files](https://learn.microsoft.com/en-us/azure/storage/files/storage-files-introduction) offers fully managed file shares in the cloud, accessible via the industry-standard SMB and NFS protocols and a REST API.

This package provides a Ballerina connector for Azure Files, backed by the official [`azure-storage-file-share`](https://learn.microsoft.com/en-us/java/api/overview/azure/storage-file-share-readme) Java SDK. It exposes:

- **`Client`**: a share-scoped client for working with the directories and files in a single share (create, upload, download, copy, rename, ranges, and more).
- **`AdminClient`**: an account-level client for managing shares (create, list, delete, restore).

> **Status: client surface implemented.** The `Client` and `AdminClient` operations are implemented over the Azure SDK and covered by tests, across shared key, SAS, connection-string, and Microsoft Entra ID authentication. A polling listener for reacting to files as they appear is planned for a later release.

## Quickstart

### Step 1: Import the connector

```ballerina
import ballerinax/azure.storage.files;
```

### Step 2: Create a client

A `Client` is bound to a single share. Authenticate with a Shared Key, a SAS token, or a connection string.

```ballerina
files:Client fileClient = check new (
    "<share-name>",
    auth = {accountName: "<account>", accountKey: "<key>"}
);
```

### Step 3: Invoke an operation

```ballerina
// Upload a local file, then read its properties back.
check fileClient->uploadFile("./local/q1.pdf", "/reports/q1.pdf");
files:FileProperties props = check fileClient->getFileProperties("/reports/q1.pdf");
```

### Manage shares with `AdminClient`

```ballerina
files:AdminClient admin = check new (auth = {accountName: "<account>", accountKey: "<key>"});
check admin->createShare("reports");
```

## Examples

The [examples](https://github.com/ballerina-platform/module-ballerinax-azure.storage.files/tree/main/examples) cover common scenarios end to end, each as a standalone Ballerina project with its own walkthrough:

1. [File backup](https://github.com/ballerina-platform/module-ballerinax-azure.storage.files/tree/main/examples/file-backup) backs up a local folder to a share and restores a file from it.
2. [Share handout](https://github.com/ballerina-platform/module-ballerinax-azure.storage.files/tree/main/examples/share-handout) uploads a report and generates a time-limited, read-only SAS URL to hand to a third party.

## Report issues

To report bugs, request new features, start discussions, or ask questions, open an issue in the [Ballerina library repository](https://github.com/ballerina-platform/ballerina-library/issues).

## Useful links

- Chat live with us via our [Discord server](https://discord.gg/ballerinalang).
- Post technical questions on Stack Overflow with the [#ballerina](https://stackoverflow.com/questions/tagged/ballerina) tag.
