# Drop folder processor

This example watches the `/incoming` folder of an Azure file share and processes each file dropped into it. A `.json` file is bound to a small `Person` record, logged, and deleted; a `.json` file that does not bind (malformed content, or a missing or mistyped field) is moved into `/failed`; every other file is logged and moved into `/processed`. Each handled file is thereby cleared out of the watched folder.

## Prerequisites

Complete the connector's [setup guide](../../README.md#setup-guide) to create a storage account, a file share, and obtain the credentials. The listener watches an existing share named `drop-folder-example` (or the name you configure) with an `/incoming` directory; to create them with the Azure CLI instead of the portal:

```bash
az storage share create --name drop-folder-example --account-name <storage account name> --account-key <storage account key>
az storage directory create --share-name drop-folder-example --name incoming --account-name <storage account name> --account-key <storage account key>
```

## Configuration

Create `Config.toml` in the example directory with the following values:

```toml
accountName = "<storage account name>"
accountKey = "<storage account key>"
# optional, defaults to "drop-folder-example"
# shareName = "my-drop-share"
```

## Run the example

```bash
bal run
```

The program starts watching the share's `/incoming` folder and runs until you stop it with `Ctrl+C`.

To see it work, upload a file into `/incoming` on the share (through the [Azure portal](https://portal.azure.com), the Azure CLI, or an SMB mount). A `.json` file should hold the fields of the example's `Person` record, for example a `person.json` containing:

```json
{"name": "Ada", "age": 36}
```

Within a few seconds the file is logged and cleared: a `.json` file is deleted (or moved into `/failed` if it does not bind to the record), and any other file is moved into `/processed`.
