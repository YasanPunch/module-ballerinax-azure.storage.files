# Changelog

This file documents all notable changes to the Ballerina Azure Files package. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-08-19

### Added

- Initial `Client` and `AdminClient` surface: share, directory, file, transfer, copy, and range operations, plus share snapshots, SAS generation, and account service configuration
- Shared key, SAS token, SAS URL, connection string, and Microsoft Entra ID authentication, with configurable retry, proxy, connection-pool, and TLS transport settings
- A polling `Listener` and `Caller` for event-style consumption: the listener watches the path given by the service's attach point (the share root when absent) and dispatches each present file to a content handler (`onFile`, or the typed `onFileText`, `onFileJson`, `onFileXml`, and `onFileCsv` variants) by file extension, with optional `@files:ServiceConfig` filters and `@files:FunctionConfig` auto-consume actions (delete or move)
- Typed content binding through the Ballerina data modules, following the shared file-modules databinding contract: matching `UploadContent` and `RetrievableType` unions (`byte[]`, `string`, `json`, `xml`, records, record arrays, and the byte and CSV record stream forms), format resolution from a `fileFormat` override or the path extension, records-only CSV binding, and a `laxDataBinding` option on the listener
- An optional `onError` service handler notified of every listener-side failure: poll failures and content-read failures as mapped typed errors, and a typed handler's content-binding failure as a `ContentBindingError` carrying the failing file's path. With `onError` declared, the binding-failed file's fate follows `onError`'s own `@files:FunctionConfig`
- A compiler plugin that validates a listener service at compile time (at least one content handler, each handler's parameter types and `error?` return, the `onError` signature, and no resource functions or unknown remote methods)
- A test suite that runs against an in-process mock of the Azure Files REST service without credentials, and against a live storage account when credentials are configured
- GraalVM native-image support (verified by running the test suite as a native executable)
