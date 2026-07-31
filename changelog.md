# Changelog

This file documents all notable changes to the Ballerina Azure Files package. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial `Client` and `AdminClient` surface: share, directory, file, transfer, copy, and range operations, plus leases, snapshots, SMB handles, access policies, SDDL share permissions, SAS generation, NFS links, and service properties
- Shared key, SAS token, SAS URL, connection string, and Microsoft Entra ID authentication, with configurable retry, proxy, connection-pool, and TLS transport settings
- A polling `Listener` and `Caller` for event-style consumption: the listener watches the path given by the service's attach point (the share root when absent) and dispatches each present file to a content handler (`onFile`, or the typed `onFileText`, `onFileJson`, `onFileXml`, and `onFileCsv` variants) by file extension, with optional `@files:ServiceConfig` filters and `@files:FunctionConfig` auto-consume actions (delete or move)
- Typed content binding through the Ballerina data modules, with XML and CSV record binding, byte and CSV stream content forms, a `laxDataBinding` option, and fail-safe CSV processing (`csvFailSafe`) that quarantines malformed records to an error log
- An optional `onError` service handler notified of poll failures (as typed errors) and content-binding failures, alongside poll errors surfacing through the listener's log
- A compiler plugin that validates a listener service at compile time (a valid content-handler set, each handler's signature, and the listener annotations)
- A test suite that runs against an in-process mock of the Azure Files REST service without credentials, and against a live storage account when credentials are configured
- GraalVM native-image support (verified by running the test suite as a native executable)
