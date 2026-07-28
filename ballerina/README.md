## Overview

[Azure Files](https://learn.microsoft.com/en-us/azure/storage/files/storage-files-introduction) offers fully managed file shares in the cloud, accessible via the industry-standard SMB and NFS protocols and a REST API.

The Azure Files connector offers APIs to connect to Azure Files and manage shares and the directories and files within them, covering uploads, downloads, copies, renames, byte ranges, snapshots, leases, and SAS token generation. It also provides a polling `Listener` that turns files arriving on a share into service events.

### Key Features

- Share-scoped `Client` for directory and file operations, transfers, copies, and byte ranges
- Account-level `AdminClient` for creating, listing, deleting, and restoring shares
- Polling `Listener` that routes files arriving on a watched path to raw or typed content handlers
- Share snapshots, leases, access policies, SMB handles, and NFS links
- Authentication with shared key, SAS tokens, connection strings, and Microsoft Entra ID
- GraalVM compatible for native image builds

## Setup guide

To use the Azure Files connector, you must have an Azure subscription and an Azure storage account. If you do not have an Azure account, you can sign up for one [here](https://azure.microsoft.com/free/).

### Step 1: Create a storage account

1. Sign in to the [Azure portal](https://portal.azure.com/).

2. Navigate to **Storage accounts** and click **+ Create**.

3. Select a subscription and resource group, provide a storage account name, and click **Review + create**. For the full set of options, see the [Azure documentation](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-create).

### Step 2: Create a file share

1. Open the storage account and navigate to **Data storage** > **File shares**.

2. Click **+ File share**, provide a name, and click **Create**. For details, see the [Azure Files documentation](https://learn.microsoft.com/en-us/azure/storage/files/storage-how-to-create-file-share).

### Step 3: Obtain the credentials

1. In the storage account, navigate to **Security + networking** > **Access keys**.

2. Copy the storage account name and one of the account keys.

The connector also accepts a SAS token or SAS URL (generated under **Security + networking** > **Shared access signature**), a connection string (shown alongside each access key), and Microsoft Entra ID credentials.

## Quickstart

To use the `azure.storage.files` connector in your Ballerina application, modify the `.bal` file as follows:

### Step 1: Import the module

```ballerina
import ballerinax/azure.storage.files;
```

### Step 2: Instantiate a new connector

A `Client` is bound to a single file share. Provide the credentials through configurable variables:

```ballerina
configurable string accountName = ?;
configurable string accountKey = ?;

files:Client fileClient = check new ("reports", auth = {accountName, accountKey});
```

### Step 3: Invoke the connector operation

Now, utilize the available connector operations.

#### Upload a file

```ballerina
check fileClient->uploadFile("./local/q1.pdf", "/reports/q1.pdf");
```

#### Get the properties of a file

```ballerina
files:FileProperties props = check fileClient->getFileProperties("/reports/q1.pdf");
```

#### Manage shares

```ballerina
files:AdminClient admin = check new (auth = {accountName, accountKey});
check admin->createShare("reports");
```

### Step 4: Run the Ballerina application

Save the changes and run the Ballerina application using the following command.

```bash
bal run
```

## Examples

The `azure.storage.files` connector provides practical examples illustrating usage in various scenarios. Explore these [examples](https://github.com/ballerina-platform/module-ballerinax-azure.storage.files/tree/main/examples), covering use cases like backing up a folder to a share, handing out a time-limited file link, and processing files dropped into a share folder.

1. [File backup](https://github.com/ballerina-platform/module-ballerinax-azure.storage.files/tree/main/examples/file-backup) - Back up a local folder to a file share and restore a file from it.
2. [Share handout](https://github.com/ballerina-platform/module-ballerinax-azure.storage.files/tree/main/examples/share-handout) - Upload a report and generate a time-limited, read-only SAS URL to share with a third party.
3. [Drop folder processor](https://github.com/ballerina-platform/module-ballerinax-azure.storage.files/tree/main/examples/drop-folder-processor) - Watch a folder on a share with the listener and process each dropped file, deleting JSON files and moving the rest into a processed folder.
