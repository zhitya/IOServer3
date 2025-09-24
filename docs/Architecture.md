# CompressorHub Software Architecture

## 1. Purpose and Scope
CompressorHub is an industrial software platform that collects telemetry from field
compressor controllers, stores the data reliably, exposes operational dashboards,
provides configurable reports, and enables secure multi-role access for operators,
data managers, and administrators. This document defines an optimal architecture
that satisfies the initial requirements while keeping the platform extensible for
future protocol additions and analytic capabilities.

## 2. Architectural Drivers
- **Protocol diversity** – support Modbus TCP/RTU today and allow new protocols such
  as OPC UA or vendor-specific APIs tomorrow.
- **Data durability and reporting** – persist high-frequency telemetry safely and
  generate Excel-based reports from historical datasets.
- **Operational visibility** – dashboards and analytics that surface trends,
  alarms, and KPI calculations to end users in near real time.
- **Security and manageability** – role-based access, audit trails, component
  version awareness, and deployment on Windows hosts.
- **Maintainability** – modular services with clear boundaries, automated
  deployment pipelines, and shared observability.

## 3. High-Level Solution Overview
The platform is organised into four logical layers:

1. **Field Interface Layer** – modular protocol adapters communicate with field
   equipment and normalise telemetry into a canonical internal model.
2. **Data Services Layer** – ingestion, validation, and persistence of telemetry,
   as well as historical querying and aggregation pipelines.
3. **Application Services Layer** – domain APIs for dashboards, reporting,
   configuration, and user management.
4. **Experience Layer** – a React-based web SPA for operator dashboards,
   configuration consoles, and report downloads.

Cross-cutting services include logging, identity and access management (IAM), job
scheduling, and monitoring. A service mesh or light-weight API gateway governs
service-to-service communication.

## 4. Logical Component Architecture
```
+-------------------+        +----------------------+        +-----------------------+
| Field Devices     |        | Field Interface      |        | Message Broker        |
| (Modbus, OPC UA)  +------->+ Service              +------->+ (RabbitMQ/Kafka)      |
+-------------------+        | - Modbus TCP Adapter |        |                       |
                             | - Modbus RTU Adapter |        +-----------------------+
                             | - OPC UA Adapter*    |                   |
                             +-----------+----------+                   v
                                         |                       +-------------+
                                         v                       | Ingestion   |
                               +-------------------+             | Service     |
                               | Edge Buffer /     |             | - Validation|
                               | Collector (optional)            | - Enrichment|
                               +-------------------+             +------+------+ 
                                                                       |
                                                                       v
        +--------------------+      +----------------------+   +--------------------+
        | Telemetry Storage  |<-----+ Historical Data API  |   | Operational Cache  |
        | (TimescaleDB/SQL)  |      | Aggregation Service  |   | (Redis)            |
        +--------------------+      +----------------------+   +--------------------+
                 |                                |                      |
                 v                                v                      v
        +---------------------+        +----------------------+  +-----------------------+
        | Reporting Service   |        | Dashboard Service    |  | User & Config Service |
        | (Excel generator)   |        | (KPI, alerts)        |  | (RBAC, templates)     |
        +---------------------+        +----------------------+  +-----------+-----------+
                 |                                |                           |
                 v                                v                           v
        +--------------------------------------------------------------------------------+
        |                      Web Application (React + ASP.NET Core APIs)              |
        +--------------------------------------------------------------------------------+
```
*Future component.

## 5. Detailed Component Responsibilities
### 5.1 Field Interface Service
- Runs as a Windows service (or container) built on .NET with pluggable protocol
  drivers.
- Supports Modbus TCP and Modbus RTU out of the box using a shared device polling
  scheduler with configurable scan rates.
- Offers a device registry that stores connection details, registers, scaling
  factors, and data types in the primary database.
- Utilises a strategy interface so additional protocols (OPC UA, MQTT, vendor
  SDKs) can be added by implementing a new adapter module without altering core
  logic.
- Emits telemetry messages in a canonical JSON/Avro schema to the message broker
  and includes device metadata, timestamp, and quality flags.

### 5.2 Messaging Backbone
- RabbitMQ (or Azure Service Bus on Windows) decouples field collection from
  downstream processing and buffers burst loads.
- Separate topics/queues for telemetry, alarms, configuration changes, and audit
  events.
- Durable queues with publisher confirms to guarantee delivery.

### 5.3 Ingestion & Processing Service
- Consumes telemetry messages and validates them against schema definitions.
- Normalises units, applies scaling, and enriches data with equipment hierarchy
  information.
- Writes high-frequency metrics to TimescaleDB (PostgreSQL extension) for
  efficient time-series queries and retention policies, and stores aggregated
  snapshots in Redis for dashboard responsiveness.
- Triggers alert rules (e.g., limit violations) and publishes events to the
  dashboard service.

### 5.4 Telemetry Storage
- **Primary store**: PostgreSQL with TimescaleDB extension (supported on Windows
  via Docker or native installation) to handle time-series compression, retention
  policies, and continuous aggregates.
- **Configuration store**: same PostgreSQL instance hosts normalized tables for
  device metadata, report templates, and user-generated settings.
- **File store**: MinIO/Azure Blob Storage for persisting generated Excel reports
  and downloadable artefacts.

### 5.5 Reporting Service
- Background worker (Hangfire or Quartz.NET) that executes report jobs on a
  schedule or on demand.
- Uses templating (EPPlus or ClosedXML libraries) to render Excel files from
  stored query results and Timescale continuous aggregates.
- Tracks report definitions (filters, grouping, KPIs) in the configuration store
  and ensures only Data Managers can modify templates.

### 5.6 Dashboard & Analytics Service
- Provides REST/GraphQL endpoints for dashboards aggregating telemetry, anomaly
  detection outputs, and alert status.
- Leverages Redis cache for near real-time trend data and falls back to
  TimescaleDB for historical ranges.
- Implements pluggable analytics modules (e.g., compressor efficiency) with
  Python microservices invoked through gRPC to support advanced analytics without
  bloating the core service.

### 5.7 User & Configuration Management Service
- Utilises ASP.NET Core Identity with Microsoft SQL Server/ PostgreSQL backend to
  manage users, password policies, MFA, and role assignments.
- Roles: **Viewer** (basic access), **Data Manager**, **Administrator**.
- Provides APIs for updating device registry, report templates, alert rules, and
  other platform settings, guarded by granular policies (e.g., Data Manager can
  modify templates but not user roles).

### 5.8 Web Application
- React SPA with TypeScript and component library (Ant Design or Material UI).
- Consumes secured REST/GraphQL APIs via OAuth2/OpenID Connect (IdentityServer or
  Azure AD B2C) with refresh tokens.
- Features include dashboards, device explorer, report scheduling/downloads,
  audit trail viewer, and administration panels.
- Responsive design to support tablets used by field engineers.

### 5.9 Logging & Audit Trail
- Centralised logging via Serilog to Elasticsearch/OpenSearch with dashboards in
  Kibana/OpenSearch Dashboards.
- Audit service listens to audit queue and stores user actions and system events
  in an append-only log table for compliance.
- Log correlation IDs propagate across services for troubleshooting.

### 5.10 Version & Component Registry
- Configuration service exposes an endpoint returning the running version of each
  microservice, UI build, database schema, and protocol adapter package.
- CI/CD pipeline injects version metadata during build; services read the data
  from embedded manifest files.

## 6. Security Considerations
- Network segmentation: locate Field Interface Service in a DMZ with firewalls and
  application-level whitelisting to isolate operational technology networks.
- TLS for all internal/external communications; Modbus RTU connections safeguarded
  through secure serial servers.
- API gateway enforces authentication (JWT tokens) and authorisation policies.
- Secrets stored in Windows Credential Manager or Azure Key Vault with automatic
  rotation.
- Extensive auditing for login attempts, configuration changes, and report
  downloads.

## 7. Deployment Topology
- **Base deployment**: Windows Server host running Docker Desktop or Windows
  containers orchestrated by Kubernetes (AKS on Azure, K3s on edge). Alternative
  single-node setup uses Windows Services.
- Field Interface Service optionally deployed close to equipment (edge gateway)
  for resilient data buffering with intermittent connectivity.
- Backend services (API, reporting, ingestion) run on application servers; shared
  PostgreSQL instance and Redis cluster provide storage; message broker and
  logging stack run as managed services or containers.
- Use Infrastructure as Code (Terraform/Ansible) to provision environments.

## 8. Extensibility & Maintainability
- Protocol adapters adhere to an interface and are packaged as NuGet modules,
  enabling protocol upgrades without redeploying the entire service.
- Reporting templates stored in versioned Git repository; editing via web UI
  triggers pull request workflow for approval when needed.
- Feature toggles (e.g., new analytics) managed via LaunchDarkly or custom table
  to enable gradual rollouts.
- Comprehensive automated tests (unit, integration, hardware-in-the-loop) and
  CI/CD pipeline (GitHub Actions/Azure DevOps) that packages services into
  signed artefacts.

## 9. Observability & Operations
- Metrics collected via OpenTelemetry and scraped by Prometheus/Grafana.
- Health check endpoints for each microservice integrated with load balancers.
- Alerting pipeline pushes notifications to e-mail, Teams, or SMS via data
  manager-configured rules.
- Backup strategy includes daily database dumps, storage replication, and report
  archive retention policies.

## 10. Data Model Overview
- **Device**: metadata, protocol configuration, register map reference.
- **TelemetryPoint**: device, timestamp, value, quality, unit.
- **AggregatedMetric**: time-bucketed summaries (min, max, avg, totals).
- **ReportTemplate**: parameters, layout definition, owning role.
- **ReportJob**: schedule, status, generated file reference.
- **AlertRule / AlertEvent**: thresholds and triggered events.
- **User / Role / AuditEvent**: IAM structures and append-only audit history.

## 11. Roadmap for Future Enhancements
1. Introduce OPC UA adapter and MQTT publisher to push filtered data to upstream
   enterprise historians.
2. Machine-learning anomaly detection microservice with retrainable models.
3. Mobile companion app leveraging the same APIs with offline data views.
4. Edge analytics packages deployed alongside Field Interface Service for
   pre-processing and bandwidth savings.

---
*This architecture balances immediate Modbus requirements with extensibility,
robust data handling, and secure operations suitable for industrial environments.*
