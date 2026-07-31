# Drop folder processor

This example watches a folder on an Azure file share and reacts to each file dropped into it. It uses the connector's `Listener`, which polls the watched path on a fixed interval and dispatches every file it finds to a matching handler. JSON files are logged and then deleted, and every other file is logged and then moved into a `/processed` folder, so each successfully handled file is cleared out of the watched folder. A JSON file that fails to bind (malformed content, or a root that is not an object) is moved into `/failed` instead. Delivery is at least once: a file that stays in the watched folder is dispatched again on a later poll, so handlers should tolerate a repeat.

## Prerequisites

1. An Azure storage account. In the [Azure portal](https://portal.azure.com), create a storage account for Azure Files (Standard performance, Pay-as-you-go file share billing), or use an existing one.
2. The account credentials. Open **Security + networking → Access keys** on the storage account and copy the storage account name and the key1 value.
3. The file share and its watched directory. Create a share named `drop-folder-example` (or the name you configure) with an `/incoming` directory, either in the portal (**Data storage → File shares → + File share**, then **+ Add directory** inside it) or with the Azure CLI:

```bash
az storage share create --name drop-folder-example --account-name <storage account name> --account-key <storage account key>
az storage directory create --share-name drop-folder-example --name incoming --account-name <storage account name> --account-key <storage account key>
```

## Configuration

Copy `Config.toml.template` in the example directory to `Config.toml` and fill in the values:

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

The program starts polling the share's `/incoming` folder and runs until you stop it with `Ctrl+C`.

To see it work, upload a file into `/incoming` on the share (through the [Azure portal](https://portal.azure.com), the Azure CLI, or the [file backup](../file-backup) example). Within a few seconds the listener logs the file: a `.json` file is logged and deleted (or moved into `/failed` if it does not hold a JSON object), and any other file is logged and moved into `/processed`.
