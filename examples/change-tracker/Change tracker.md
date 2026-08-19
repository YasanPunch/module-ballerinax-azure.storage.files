# Change tracker

This example reports what changed on an Azure file share since it last ran. Each run lists the share, compares it against the snapshot saved by the previous run, logs a "file created", "file modified", or "file deleted" event for every difference, saves the new snapshot to `snapshot.json`, and exits. Run it on a schedule (for example from cron or a Kubernetes CronJob) to turn the share into a periodic stream of change events without a continuously running process.

## Prerequisites

Complete the connector's [setup guide](../../README.md#setup-guide) to create a storage account, a file share, and obtain the credentials. The tracker watches an existing share named `change-tracker-example` (or the name you configure); to create it with the Azure CLI instead of the portal:

```bash
az storage share create --name change-tracker-example --account-name <storage account name> --account-key <storage account key>
```

## Configuration

Create `Config.toml` in the example directory with the following values:

```toml
accountName = "<storage account name>"
accountKey = "<storage account key>"
# optional, defaults to "change-tracker-example"
# shareName = "my-watched-share"
# optional, defaults to "snapshot.json"
# snapshotFile = "/var/lib/change-tracker/snapshot.json"
```

## Run the example

```bash
bal run
```

The first run reports every file on the share as created: there is no previous snapshot, so the first scan is the baseline. To see the three events, upload a file to the share (through the [Azure portal](https://portal.azure.com), the Azure CLI, or an SMB mount) and run the example again for a "file created" log line. Overwrite the same file with different content and run again for "file modified", and delete it and run once more for "file deleted".
