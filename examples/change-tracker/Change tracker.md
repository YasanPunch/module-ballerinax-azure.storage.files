# Change tracker

This example turns a watched Azure file share into a stream of change events: it logs a "file created", "file modified", or "file deleted" event for every change on the share, derived entirely on the application side. The connector's `Listener` is deliberately stateless. Azure Files keeps no change feed, so the listener reports what is present on every poll and remembers nothing between polls; producing change events therefore means the application keeps its own state, and this example shows the pattern. It tracks each file's entity tag (the value Azure changes on every write) and last-modified time in an in-memory snapshot: a dispatched file missing from the snapshot is a creation, one whose entity tag differs is a modification, and files are never consumed, so the listener keeps re-dispatching what is present and unchanged files are simply ignored. A presence listener cannot observe absence, so deletions come from a second schedule that lists the share and reconciles the snapshot against what actually exists.

## Prerequisites

1. An Azure storage account. In the [Azure portal](https://portal.azure.com), create a storage account for Azure Files (Standard performance, Pay-as-you-go file share billing), or use an existing one.
2. The account credentials. Open **Security + networking → Access keys** on the storage account and copy the storage account name and the key1 value.
3. The file share. The tracker watches an existing share, so create it before running: a share named `change-tracker-example` (or the name you configure), either in the portal (**Data storage → File shares → + File share**; the connector's [setup guide](../../README.md#step-2-create-a-file-share) walks through this with screenshots) or with the Azure CLI:

```bash
az storage share create --name change-tracker-example --account-name <storage account name> --account-key <storage account key>
```

Creating a share from Ballerina code is shown in the [file backup](../file-backup) example, which provisions its own share with the connector's `AdminClient`.

## Configuration

Create `Config.toml` in the example directory with the following values:

```toml
accountName = "<storage account name>"
accountKey = "<storage account key>"
# optional, defaults to "change-tracker-example"
# shareName = "my-watched-share"
```

## Run the example

```bash
bal run
```

The program polls the share and runs until you stop it with `Ctrl+C`. On the first poll every file already on the share is reported as created: the snapshot starts empty, so the first scan is the baseline.

To see the three events, upload a file to the share (through the [Azure portal](https://portal.azure.com), the Azure CLI, or an SMB mount) and watch a "file created" log line appear within a few seconds. Overwrite the same file with different content for "file modified", and delete it for "file deleted".

## What this pattern trades for

The snapshot lives in memory, so the guarantees are exactly what the application code makes them. A restart re-baselines: every file present is reported as created again, and deletions that happened while the tracker was down are never reported. The listener's delivery is at least once, which this pattern absorbs naturally: re-observing an unchanged file is a no-op, so duplicate dispatches cost nothing. The entity tag is the precise change signal (Azure assigns a new one on every write); the last-modified timestamp is carried alongside for display, and an application that prefers it can compare it instead. An application that needs the snapshot to survive restarts can persist it (for example to a local file, or to a file on the share itself) instead of holding it in memory.
