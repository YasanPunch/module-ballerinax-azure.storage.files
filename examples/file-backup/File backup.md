# File backup

This example backs up a local folder to an Azure file share and restores a file from it. It creates the share when it does not exist, uploads every file from a local `data` folder into a `/daily` directory on the share, lists the share's contents recursively, and downloads one file back to disk.

## Prerequisites

1. An Azure storage account. In the [Azure portal](https://portal.azure.com), create a storage account for Azure Files (Standard performance, Pay-as-you-go file share billing), or use an existing one.
2. The account credentials. Open **Security + networking → Access keys** on the storage account and copy the storage account name and the key1 value.

## Configuration

Create a `Config.toml` file in the example directory:

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
