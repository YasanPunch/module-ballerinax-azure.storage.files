# Share handout

This example shares a file with a third party without sharing the account credentials. It creates a share, uploads a report to it, and generates a time-limited, read-only shared access signature (SAS) URL scoped to that single file. Anyone with the URL can read the report, and nothing else on the share, for 24 hours; after that the link expires on its own.

## Prerequisites

Complete the connector's [setup guide](../../README.md#setup-guide) to create a storage account and obtain the credentials. This example creates its own share.

## Configuration

Create `Config.toml` in the example directory with the following values:

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
