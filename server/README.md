# POSFlutter Server

ASP.NET Core/.NET 10 backend for the POSFlutter offline-first client.

## Projects

- `src/Domain` — entities and core persistence model.
- `src/Application` — contracts, abstractions and application rules.
- `src/Infrastructure` — EF Core SQL Server context, JWT/refresh, tenancy reads, sync and device enrollment.
- `src/Api` — HTTP host, auth/bootstrap/sync/enrollment/read endpoints, health/OpenAPI.
- `tests/Infrastructure.Tests` — reconstructed xUnit tests.

## Build/test when .NET 10 is available

From `server/`:

```text
dotnet restore
dotnet build
dotnet test
```

Not executed in the reconstruction runtime: .NET SDK is absent.

## Configuration

Do not commit secrets. Supply at runtime:

```text
ConnectionStrings__SqlServer=<real SQL Server connection string>
Jwt__SigningKey=<strong private signing key>
```

`server/.env.example` contains placeholders only.

## EF Core migration pending

No EF migration was manually fabricated during reconstruction. Once `dotnet ef` is available, generate/review a migration from the actual reconstructed model using the real project paths:

```text
dotnet ef migrations add ReconstructedBaseline --project src/Infrastructure/Infrastructure.csproj --startup-project src/Api/Api.csproj --output-dir Migrations
```

Then inspect the generated migration before applying it to any database.

## Tenant/security model

Authenticated operations derive Business/Branch/Device/User context from signed claims and validate current device state where required. Operational `sync push` is restricted to active `PointOfSale` devices. `AdminReadOnly` devices may authenticate, pull and use tenant-safe read endpoints but cannot use operational writes.

Enrollment codes use 256-bit randomness and only SHA-256 hashes are stored. Redemption additionally requires Administrator credentials for the same business and uses a stable client `DeviceGlobalId` for lost-response idempotency.
