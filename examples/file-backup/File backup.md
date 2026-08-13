# File backup

This example backs up a local folder to an Azure file share and restores a file from it. It creates the share when it does not exist, uploads every file from a local `data` folder into a `/daily` directory on the share, lists the share's contents recursively, and downloads one file back to disk.

## Prerequisites

Complete the connector's [setup guide](../../README.md#setup-guide) to create a storage account and obtain the credentials. This example creates its own share.

## Configuration

Create `Config.toml` in the example directory with the following values:

```toml
accountName = "<storage account name>"
accountKey = "<storage account key>"
# optional, defaults to "backup-example"
# shareName = "my-backup-share"
```

## Run the example

```bash
bal run
```

The program prints each uploaded file, the recursive share listing, and the content of the restored file.
