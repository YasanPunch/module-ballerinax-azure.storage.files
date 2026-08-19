# Examples

The `ballerinax/azure.storage.files` connector provides practical examples illustrating usage in various scenarios. Each example is a standalone Ballerina project with its own walkthrough.

1. [File backup](file-backup) — continuously back up a local folder: a directory listener watches it and uploads every new file to an Azure file share.
2. [Share handout](share-handout) — upload a report to a share and generate a time-limited, read-only SAS URL that can be handed to a third party.
3. [Drop folder processor](drop-folder-processor) — watch a folder on a share with the listener and process each dropped file, deleting JSON files and moving the rest into a processed folder.
4. [Change tracker](change-tracker) — a schedulable program that diffs a share against the snapshot saved by its previous run and logs created, modified, and deleted events.

## Prerequisites

Each example needs an Azure storage account and its access key; the connector's [setup guide](../README.md#setup-guide) walks through creating them. Each example's walkthrough documents the `Config.toml` to create in the example directory.

## Running an example

Execute the following commands inside the example's directory:

```bash
bal build
bal run
```

## Building the examples against the local code

When changing the connector itself, build the examples against the local package rather than the released one:

```bash
./build.sh build
```

The script packs the `ballerina/` package into the local repository and builds every example offline against it. `./build.sh run` runs the examples the same way, which needs a `Config.toml` with credentials in each example directory.
