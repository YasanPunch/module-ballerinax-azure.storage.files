# Drop folder processor

This example watches a folder on an Azure file share and reacts to each file dropped into it. It uses the connector's `Listener`, which polls the watched path on a fixed interval and dispatches every file it finds to a matching handler. JSON files are logged and then deleted, and every other file is logged and then moved into a `/processed` folder, so each successfully handled file is cleared out of the watched folder. A JSON file that fails to bind (malformed content, or a root that is not an object) is moved into `/failed` instead. Delivery is at least once: a file that stays in the watched folder is dispatched again on a later poll, so handlers should tolerate a repeat.

## Prerequisites

1. An Azure storage account. In the [Azure portal](https://portal.azure.com), create a storage account for Azure Files (Standard performance, Pay-as-you-go file share billing), or use an existing one.
2. The account credentials. Open **Security + networking → Access keys** on the storage account and copy the storage account name and the key1 value.

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

The program creates the share and its `/incoming` folder on the first run, then keeps polling. It runs until you stop it with `Ctrl+C`.

To see it work, upload a file into `/incoming` on the share (through the [Azure portal](https://portal.azure.com), the Azure CLI, or the [file backup](../file-backup) example). Within a few seconds the listener logs the file: a `.json` file is logged and deleted (or moved into `/failed` if it does not hold a JSON object), and any other file is logged and moved into `/processed`.
