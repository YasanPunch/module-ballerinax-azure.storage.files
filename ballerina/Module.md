## Overview

[Azure Files](https://learn.microsoft.com/en-us/azure/storage/files/storage-files-introduction) offers fully managed file shares in the cloud, accessible via the industry-standard SMB and NFS protocols and a REST API.

This module provides a Ballerina connector for Azure Files, backed by the official [`azure-storage-file-share`](https://learn.microsoft.com/en-us/java/api/overview/azure/storage-file-share-readme) Java SDK. It exposes:

- **`Client`** — a share-scoped client for working with the directories and files in a single share (create, upload, download, copy, rename, ranges, and more).
- **`AdminClient`** — an account-level client for managing shares (create, list, delete, restore).
- **`Listener`** — a polling listener that watches a share and dispatches `onFileAdd`, `onFileDelete`, and `onFileModify` events to a service, with a `Caller` for acting on the file that triggered each event.

> **Status: API skeleton.** This is the first-release (v0.1) API surface with stubbed operation bodies, published for design review ahead of implementation. Operations currently return a `NotImplemented` error.

## Quickstart

### Step 1: Import the connector

```ballerina
import ballerinax/azure.storage.files;
```

### Step 2: Create a client

A `Client` is bound to a single share. Authenticate with a Shared Key, a SAS token, or a connection string.

```ballerina
files:Client fileClient = check new (
    {accountName: "<account>", auth: {accountKey: "<key>"}},
    "<share-name>"
);
```

### Step 3: Invoke an operation

```ballerina
// Upload a local file, then read its properties back.
check fileClient->upload("reports/q1.pdf", "./local/q1.pdf");
files:Properties props = check fileClient->getProperties("reports/q1.pdf");
```

### Manage shares with `AdminClient`

```ballerina
files:AdminClient admin = check new ({accountName: "<account>", auth: {accountKey: "<key>"}});
check admin->createShare("reports");
```

### Watch a share with `Listener`

```ballerina
listener files:Listener fileListener = new ({
    accountName: "<account>",
    auth: {accountKey: "<key>"},
    shareName: "reports"
});

service on fileListener {
    remote function onFileAdd(files:FileInfo file, files:Caller caller) returns error? {
        // handle the newly added file
    }
}
```
