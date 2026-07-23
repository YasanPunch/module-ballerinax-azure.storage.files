# Examples

The `ballerinax/azure.storage.files` connector provides practical examples illustrating usage in various scenarios. Each example is a standalone Ballerina project with its own walkthrough.

1. [File backup](file-backup) — back up a local folder to an Azure file share, list the share's contents recursively, and restore a file from the backup.
2. [Share handout](share-handout) — upload a report to a share and generate a time-limited, read-only SAS URL that can be handed to a third party.

## Prerequisites

Each example needs an Azure storage account and its access key; the walkthrough inside each example describes the setup, and each example carries a `Config.toml.template` to copy to `Config.toml` and fill in.

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
