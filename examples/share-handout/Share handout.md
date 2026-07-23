# Share handout

This example shares a file with a third party without sharing the account credentials. It creates a share, uploads a report to it, and generates a time-limited, read-only shared access signature (SAS) URL that can be handed out. Anyone with the URL can read the report for 24 hours; after that the link expires on its own.

## Prerequisites

1. An Azure storage account. In the [Azure portal](https://portal.azure.com), create a storage account for Azure Files (Standard performance, Pay-as-you-go file share billing), or use an existing one.
2. The account credentials. Open **Security + networking → Access keys** on the storage account and copy the storage account name and the key1 value.

## Configuration

Create a `Config.toml` file in the example directory:

```toml
accountName = "<storage account name>"
accountKey = "<storage account key>"
# optional, defaults to "handout-example"
# shareName = "my-report-share"
```

## Run the example

```bash
bal run
```

The program prints a URL carrying the SAS token. Opening it in a browser (or fetching it with `curl`) downloads the report without any further authentication.
