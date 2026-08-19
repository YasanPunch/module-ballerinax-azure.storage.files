# Share handout

This example shares a file with a third party without sharing the account credentials. It uploads a report to a share, and generates a time-limited, read-only shared access signature (SAS) URL scoped to that single file. Anyone with the URL can read the report, and nothing else on the share, for 24 hours; after that the link expires on its own.

## Prerequisites

Complete the connector's [setup guide](../../README.md#setup-guide) to create a storage account, a file share, and obtain the credentials. The example expects an existing share named `handout-example` (or the name you configure); to create it with the Azure CLI instead of the portal:

```bash
az storage share create --name handout-example --account-name <storage account name> --account-key <storage account key>
```

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
