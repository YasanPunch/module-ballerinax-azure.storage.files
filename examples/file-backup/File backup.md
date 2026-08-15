# File backup

This example continuously backs up a local folder to an Azure file share. It watches the folder with a local directory listener, and every file created in it is uploaded to the share as it appears, so dropping a file into the folder is all it takes to back it up.

## Prerequisites

Complete the connector's [setup guide](../../README.md#setup-guide) to create a storage account, a file share, and obtain the credentials. The example expects an existing share named `backup-example` (or the name you configure); to create it with the Azure CLI instead of the portal:

```bash
az storage share create --name backup-example --account-name <storage account name> --account-key <storage account key>
```

## Configuration

Create `Config.toml` in the example directory with the following values:

```toml
accountName = "<storage account name>"
accountKey = "<storage account key>"
# optional, defaults to "backup-example"
# shareName = "my-backup-share"
# optional, defaults to "backup" (relative to the working directory)
# watchedFolder = "/path/to/folder"
```

## Run the example

```bash
bal run
```

The program creates the watched folder when it is absent, starts watching it, and runs until you stop it with `Ctrl+C`.

To see it work, copy a file into the watched folder; the sample under `resources/` is there to try:

```bash
cp resources/notes.txt backup/
```

Within a moment the program logs the upload, and the file appears on the share (visible in the [Azure portal](https://portal.azure.com) under the share's root, or with `az storage file list`).
