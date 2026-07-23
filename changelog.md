# Changelog

This file documents all notable changes to the Ballerina Azure Files package. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial `Client` and `AdminClient` surface: share, directory, file, transfer, copy, and range operations, plus leases, snapshots, SMB handles, access policies, SDDL share permissions, SAS generation, NFS links, and service properties
- Shared key, SAS token, SAS URL, connection string, and Microsoft Entra ID authentication, with configurable retry, proxy, connection-pool, and TLS transport settings
- A test suite that runs against an in-process mock of the Azure Files REST service without credentials, and against a live storage account when credentials are configured
