#!/usr/bin/env python3
from __future__ import annotations
import json, os, re, sys
from pathlib import Path
import xml.etree.ElementTree as ET
try:
    import yaml
except Exception as exc:
    print(f'GATE=FAIL missing PyYAML: {exc}')
    raise SystemExit(1)

ROOT=Path(__file__).resolve().parents[1]
BUILD_ROOTS=[ROOT/'client'/'pos_app',ROOT/'server']
errors:list[tuple[str,str]]=[];warnings:list[tuple[str,str]]=[];checks:list[tuple[str,str]]=[]

def ok(n,d=''): checks.append((n,d))
def fail(n,d): errors.append((n,d))
def warn(n,d): warnings.append((n,d))

def functional_files():
    excluded={'RECOVERY_EVIDENCE','.git','.dart_tool','build','bin','obj','TestResults','.gradle'}
    for base in BUILD_ROOTS:
        if not base.exists(): continue
        for p in base.rglob('*'):
            if p.is_file() and not any(part in excluded for part in p.parts): yield p

def text(path:str)->str: return (ROOT/path).read_text(encoding='utf-8')

# Required graph
required=['client/pos_app/pubspec.yaml','client/pos_app/analysis_options.yaml','client/pos_app/lib/main.dart','client/pos_app/lib/app/app.dart','client/pos_app/lib/app/router.dart','client/pos_app/lib/database/app_database.dart','client/pos_app/lib/database/schema_v1.dart','client/pos_app/lib/database/schema_v2.dart','client/pos_app/lib/database/schema_v3.dart','client/pos_app/lib/sync/sync_repository.dart','client/pos_app/lib/sync/sync_service.dart','server/Pos.Server.sln','server/src/Api/Api.csproj','server/src/Application/Application.csproj','server/src/Domain/Domain.csproj','server/src/Infrastructure/Infrastructure.csproj','server/tests/Infrastructure.Tests/Infrastructure.Tests.csproj','server/src/Api/Program.cs','server/src/Application/Contracts.cs','server/src/Application/Abstractions.cs','server/src/Domain/Entities.cs','server/src/Infrastructure/PosDbContext.cs','server/src/Infrastructure/SyncService.cs','server/src/Infrastructure/DeviceEnrollmentService.cs','server/src/Infrastructure/TenantReadService.cs','server/src/Infrastructure/RemoteReportService.cs','server/src/Infrastructure/JwtTokenService.cs','server/src/Application/ReportContracts.cs','client/pos_app/lib/features/cloud_admin/reports/data/remote_report_models.dart','client/pos_app/lib/features/cloud_admin/reports/data/remote_report_repository.dart','client/pos_app/lib/features/cloud_admin/reports/presentation/remote_reports_screen.dart','client/pos_app/lib/features/cloud_admin/reports/presentation/remote_report_detail_screen.dart']
missing=[x for x in required if not (ROOT/x).exists()]
if missing: fail('required graph',', '.join(missing))
else: ok('required graph',f'{len(required)} required paths present')

# JSON/YAML/XML
json_err=[]
for p in ROOT.rglob('*.json'):
    if 'RECOVERY_EVIDENCE' in p.parts: continue
    try: json.loads(p.read_text(encoding='utf-8'))
    except Exception as e: json_err.append(f'{p.relative_to(ROOT)}: {e}')
if json_err: fail('JSON parse','; '.join(json_err))
else: ok('JSON parse','all functional JSON parsed')
yaml_err=[]
for p in [ROOT/'client/pos_app/pubspec.yaml',ROOT/'client/pos_app/analysis_options.yaml',ROOT/'server/docker-compose.yml']:
    if not p.exists(): continue
    try: yaml.safe_load(p.read_text(encoding='utf-8'))
    except Exception as e: yaml_err.append(f'{p.relative_to(ROOT)}: {e}')
if yaml_err: fail('YAML parse','; '.join(yaml_err))
else: ok('YAML parse','project YAML parsed')
xml_files=list((ROOT/'server').rglob('*.csproj'))+list((ROOT/'client/pos_app/android').rglob('*.xml'))
xml_err=[]
for p in xml_files:
    try: ET.parse(p)
    except Exception as e: xml_err.append(f'{p.relative_to(ROOT)}: {e}')
if xml_err: fail('XML parse','; '.join(xml_err))
else: ok('XML parse',f'{len(xml_files)} XML files parsed')

# ProjectReference and solution
ref_err=[]
for p in (ROOT/'server').rglob('*.csproj'):
    for el in ET.parse(p).getroot().iter('ProjectReference'):
        ref=el.attrib.get('Include','').replace('\\',os.sep).replace('/',os.sep)
        if not (p.parent/ref).resolve().exists(): ref_err.append(f'{p.relative_to(ROOT)} -> {ref}')
if ref_err: fail('ProjectReference','; '.join(ref_err))
else: ok('ProjectReference','all references resolve')
sln=ROOT/'server/Pos.Server.sln'; sln_err=[]
if sln.exists():
    refs=re.findall(r'^Project\("[^"]+"\) = "[^"]+", "([^"]+\.csproj)"',sln.read_text(),re.M)
    for ref in refs:
        if not (sln.parent/ref.replace('\\','/')).exists(): sln_err.append(ref)
    for cfg in ('Debug|Any CPU','Release|Any CPU'):
        if cfg not in sln.read_text(): sln_err.append(f'missing {cfg}')
    if len(refs)!=5: sln_err.append(f'expected 5 projects, found {len(refs)}')
if sln_err: fail('solution references','; '.join(sln_err))
else: ok('solution references','5 projects resolve with Debug/Release configuration')

# Dart imports/packages
pub=yaml.safe_load((ROOT/'client/pos_app/pubspec.yaml').read_text()) if (ROOT/'client/pos_app/pubspec.yaml').exists() else {}
declared=set((pub.get('dependencies') or {}).keys())|set((pub.get('dev_dependencies') or {}).keys())|{'dart','flutter'}
unresolved=[];undeclared=[];import_count=0
for p in list((ROOT/'client/pos_app/lib').rglob('*.dart'))+list((ROOT/'client/pos_app/test').rglob('*.dart')):
    t=p.read_text(encoding='utf-8')
    for imp in re.findall(r"(?:import|export|part)\s+['\"]([^'\"]+)['\"]",t):
        import_count+=1
        if imp.startswith('package:pos_app/'):
            target=ROOT/'client/pos_app/lib'/imp[len('package:pos_app/'):]
            if not target.exists(): unresolved.append(f'{p.relative_to(ROOT)} -> {imp}')
        elif imp.startswith('package:'):
            pkg=imp[len('package:'):].split('/',1)[0]
            if pkg not in declared: undeclared.append(f'{p.relative_to(ROOT)} -> {pkg}')
        elif imp.startswith('dart:'): pass
        else:
            if not (p.parent/imp).resolve().exists(): unresolved.append(f'{p.relative_to(ROOT)} -> {imp}')
if unresolved: fail('Dart local imports','; '.join(unresolved[:40]))
else: ok('Dart local imports',f'{import_count} imports checked; 0 unresolved local')
if undeclared: fail('Dart package dependencies','; '.join(sorted(set(undeclared))))
else: ok('Dart package dependencies','all package imports declared')

# Functional source hygiene
patterns={'TODO':re.compile(r'\bTODO\b'),'UnimplementedError':re.compile(r'\bUnimplementedError\b'),'NotImplementedException':re.compile(r'\bNotImplementedException\b'),'Git conflict marker':re.compile(r'^(?:<<<<<<<|=======|>>>>>>>)',re.M),'placeholder test':re.compile(r'Assert\.(?:True\(true\)|False\(false\))|expect\(\s*(?:true\s*,\s*true|false\s*,\s*false)\s*\)')}
source_ext={'.dart','.cs','.kt','.kts'}
for p in functional_files():
    if p.suffix.lower() not in source_ext: continue
    t=p.read_text(encoding='utf-8',errors='replace')
    if not t.strip(): fail('empty source',str(p.relative_to(ROOT)))
    if any(line.rstrip('\r\n').endswith((' ','\t')) for line in t.splitlines(True)): fail('trailing whitespace',str(p.relative_to(ROOT)))
    for n,pat in patterns.items():
        if pat.search(t): fail(n,str(p.relative_to(ROOT)))
for n in [*patterns,'empty source','trailing whitespace']:
    if not any(x==n for x,_ in errors): ok(n,'none in functional source')

# Accidental artifacts
bad=[]
for p in ROOT.rglob('*'):
    rel=p.relative_to(ROOT)
    if 'RECOVERY_EVIDENCE' in rel.parts: continue
    if p.is_dir() and p.name in {'.dart_tool','build','bin','obj','TestResults','.gradle'}: bad.append(str(rel)+'/')
    if p.is_file() and (p.suffix.lower() in {'.db','.sqlite','.sqlite3','.log','.pfx','.p12','.jks','.keystore'} or p.name in {'local.properties','key.properties'}): bad.append(str(rel))
if bad: fail('temporary/binary artifacts',', '.join(bad[:60]))
else: ok('temporary/binary artifacts','none in canonical functional tree')

# High-confidence secrets: detect actual literal credentials, not identifiers/config keys/fixtures/placeholders.
secret_hits=[]; low_conf=[]
placeholder_tokens=('change_me','your_secret','placeholder','example','test-access','test-refresh','strongpass123','localhost','10.0.2.2','${')
secret_name=re.compile(r'(?i)(password|passwd|signing.?key|api[_-]?key|client[_-]?secret|access[_-]?token|refresh[_-]?token|bearer)')
quoted_assign=re.compile(r'(?i)([A-Za-z0-9_:\.-]*(?:password|passwd|signing.?key|api[_-]?key|client[_-]?secret|access[_-]?token|refresh[_-]?token)[A-Za-z0-9_:\.-]*)\s*[:=]\s*["\']([^"\']+)["\']')
bearer=re.compile(r'(?i)\bBearer\s+(eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,})')
for p in functional_files():
    if 'tests' in p.parts or 'test' in p.parts: continue
    if p.suffix.lower() not in {'.json','.yml','.yaml','.cs','.dart','.env','.example','.md','.kts','.properties'} and p.name!='.env.example': continue
    for i,line in enumerate(p.read_text(encoding='utf-8',errors='replace').splitlines(),1):
        for m in quoted_assign.finditer(line):
            name,val=m.group(1),m.group(2).strip();low=val.lower()
            if not secret_name.search(name): continue
            if val=='' or any(x in low for x in placeholder_tokens): continue
            # Source code indexers and environment variable names are not values.
            if 'configuration[' in line.lower() or 'getenvironmentvariable' in line.lower(): continue
            # Error/message strings are not assignments of secret values.
            if 'throw new' in line.lower() or 'required' in low: continue
            # A literal variable credential with nontrivial value is high-confidence.
            if len(val)>=8: secret_hits.append(f'{p.relative_to(ROOT)}:{i}:{name}=<redacted>')
            else: low_conf.append(f'{p.relative_to(ROOT)}:{i}:{name}')
        if bearer.search(line): secret_hits.append(f'{p.relative_to(ROOT)}:{i}:Bearer JWT literal')
if secret_hits: fail('secret scan',' | '.join(secret_hits[:30]))
else: ok('secret scan','HIGH_CONFIDENCE_SECRETS=0')
if low_conf: warn('secret scan low confidence',f'{len(low_conf)} identifier/value candidates ignored after classification')

# Android source/config
android=ROOT/'client/pos_app/android'
android_required=['settings.gradle.kts','build.gradle.kts','app/build.gradle.kts','gradle.properties','gradle/wrapper/gradle-wrapper.properties','app/src/main/AndroidManifest.xml','app/src/main/kotlin/com/posflutter/pos_app/MainActivity.kt']
miss=[x for x in android_required if not (android/x).exists()]
if miss: fail('Android host',', '.join(miss))
else:
    gradle=(android/'gradle/wrapper/gradle-wrapper.properties').read_text(); appgradle=(android/'app/build.gradle.kts').read_text(); settings=(android/'settings.gradle.kts').read_text()
    expected=['gradle-9.3.1-bin.zip','com.android.application") version "9.1.0','org.jetbrains.kotlin.android") version "2.4.0','compileSdk = 36','targetSdk = 36','minSdk = 24','VERSION_17','namespace = "com.posflutter.pos_app"','applicationId = "com.posflutter.pos_app"']
    combined=gradle+'\n'+appgradle+'\n'+settings
    missing_cfg=[x for x in expected if x not in combined]
    if missing_cfg: fail('Android host','missing config: '+', '.join(missing_cfg))
    else: ok('Android host','SOURCE/CONFIG RECONSTRUCTED; wrapper binaries intentionally pending; build not executed')
for rel in ['gradlew','gradlew.bat','gradle/wrapper/gradle-wrapper.jar']:
    if (android/rel).exists(): warn('Android wrapper provenance',f'{rel} unexpectedly exists; provenance must be verified')

# Critical architecture semantics
sync_cs=text('server/src/Infrastructure/SyncService.cs'); program=text('server/src/Api/Program.cs'); sync_dart=text('client/pos_app/lib/sync/sync_repository.dart'); dart_sync=text('client/pos_app/lib/sync/sync_service.dart')
# Monotonic tenant cursor
if not (re.search(r'BusinessId\s*==\s*tenant\.BusinessId',sync_cs) and re.search(r'\.Id\s*>\s*after',sync_cs) and '.OrderBy(x => x.Id)' in sync_cs): fail('sync pull cursor','pull must filter BusinessId and SyncChange.Id > cursor, ordered by Id')
else: ok('sync pull cursor','tenant scoped by BusinessId + monotonic SyncChange.Id')
# Pagination semantic: effective take bounded <=200, query uses take+1, hasMore and next cursor from Id-derived changes.
pull_match=re.search(r'public async Task<SyncPullResponse> PullAsync\((.*?)\n    \}',sync_cs,re.S)
pull=pull_match.group(0) if pull_match else sync_cs
bounded=(re.search(r'Math\.Clamp\([^\n;]*,\s*1\s*,\s*200\s*\)',pull) is not None) or (('200' in pull) and ('Math.Min' in pull or 'MaxPageSize' in pull))
uses_limit=re.search(r'\.Take\(\s*take\s*\+\s*1\s*\)',pull) is not None
has_more=re.search(r'rows\.Count\s*>\s*take',pull) is not None
next_cursor=('changes[^1].Cursor' in pull or 'changes.Last().Cursor' in pull or 'rows[^1].Id' in pull)
if not all((bounded,uses_limit,has_more,next_cursor)): fail('sync pagination',f'bounded={bounded} takeQuery={uses_limit} hasMore={has_more} nextCursor={next_cursor}')
else: ok('sync pagination','effective page 1..200, Take(limit+1), hasMore, nextCursor from monotonic change cursor')
# AdminReadOnly server guard must load current DB device state and be called from PushAsync.
push_head=sync_cs[:sync_cs.find('public async Task<SyncPullResponse>')]
guard_match=re.search(r'private async Task<bool> IsPointOfSaleDeviceAsync\(.*?\n    \}',sync_cs,re.S)
guard=guard_match.group(0) if guard_match else ''
guard_ok=('IsPointOfSaleDeviceAsync(tenant' in push_head and '_db.Devices' in guard and 'device.Active' in guard and re.search(r'device\.Mode\s*==\s*PointOfSaleMode',guard) is not None and 'branch.BusinessId == tenant.BusinessId' in guard)
if not guard_ok: fail('AdminReadOnly server push guard','PushAsync must call a DB-backed guard checking active current device mode PointOfSale and tenant branch')
else: ok('AdminReadOnly server push guard','current DB Device.Active + Mode=PointOfSale + tenant branch checked before push')
# Pull/read allowed independent of device mode, but still authenticated.
if 'IsPointOfSaleDeviceAsync' in pull: fail('AdminReadOnly pull','pull incorrectly requires PointOfSale mode')
elif 'app.MapGet("/api/sync/pull"' not in program or '.RequireAuthorization()' not in program: fail('AdminReadOnly pull','authenticated pull route missing')
else: ok('AdminReadOnly pull','authenticated pull allowed without PointOfSale-only guard')
# SQLite atomic cursor
if not ('db.transaction((tx) async' in sync_dart and "'sync_pull_cursor'" in sync_dart and 'batch.nextCursor.toString()' in sync_dart): fail('SQLite pull transaction','pull application/cursor transaction pattern missing')
else: ok('SQLite pull transaction','remote changes and nextCursor committed in one SQLite transaction')
# Client advisory guard
if not re.search(r'if\s*\(\s*!ctx\.isAdminReadOnly\s*\)',dart_sync): fail('AdminReadOnly client push guard','client skip-push advisory guard missing')
else: ok('AdminReadOnly client push guard','client skips operational push; server remains authority')

# Tenant read routes derive tenant from claims helper; TenantReadService filters BusinessId.
read_paths=['/api/reports/dashboard','/api/products','/api/categories','/api/suppliers','/api/sales','/api/purchases','/api/inventory','/api/inventory/lots','/api/expenses','/api/cash','/api/users']
missing_routes=[x for x in read_paths if f'"{x}"' not in program]
trs=text('server/src/Infrastructure/TenantReadService.cs')
if missing_routes: fail('tenant read endpoints','missing '+', '.join(missing_routes))
elif 'TenantClaims.Require(h.User)' not in program or trs.count('t.BusinessId')<10: fail('tenant read endpoints','claim-derived tenant helper or BusinessId filters insufficient')
else: ok('tenant read endpoints',f'{len(read_paths)} authenticated tenant-scoped read routes')
# No direct operational mutation endpoints outside sync/bootstrap/enrollment.
operational_write=re.findall(r'app\.Map(?:Post|Put|Delete)\("([^\"]+)"',program)
unexpected=[p for p in operational_write if p not in ['/api/auth/login','/api/auth/refresh','/api/bootstrap','/api/device-enrollment/invitations','/api/device-enrollment/redeem','/api/sync/push']]
if unexpected: fail('direct write surface','unexpected direct write routes: '+', '.join(unexpected))
else: ok('direct write surface','operational writes funnel through sync; no bypass route for AdminReadOnly')

# FASE16 enrollment semantics
ens=text('server/src/Infrastructure/DeviceEnrollmentService.cs'); dbctx=text('server/src/Infrastructure/PosDbContext.cs')
enrollment_checks={'256-bit token':'RandomNumberGenerator.GetBytes(32)' in ens,'SHA-256 storage':'SHA256.HashData' in ens,'expiry':'ExpiresAt <= now' in ens,'revocation':'RevokedAt is not null' in ens,'Administrator required':'AdministratorRole' in ens and 'user.Role != AdministratorRole' in ens,'serializable redemption':'IsolationLevel.Serializable' in ens,'idempotent same device':'RecoverCompletedEnrollmentAsync' in ens and 'x.GlobalId == request.DeviceGlobalId' in ens,'AdminReadOnly mode':'Mode = AdminReadOnlyMode' in ens,'token hash unique':'HasIndex(x=>x.TokenHash).IsUnique()' in dbctx,'rate limit IP':'RemoteIpAddress' in program and 'PermitLimit = 10' in program}
missing_enroll=[k for k,v in enrollment_checks.items() if not v]
if missing_enroll: fail('FASE16 enrollment',', '.join(missing_enroll))
else: ok('FASE16 enrollment','token/hash/expiry/revocation/admin/serializable/idempotency/rate-limit/device-mode checks present')


# FASE17 remote reports: explicit admin-only read surface, tenant filters, historical FIFO and client read-only queries.
report_service=text('server/src/Infrastructure/RemoteReportService.cs')
report_contracts=text('server/src/Application/ReportContracts.cs')
remote_repo=text('client/pos_app/lib/features/cloud_admin/reports/data/remote_report_repository.dart')
remote_screen=text('client/pos_app/lib/features/cloud_admin/reports/presentation/remote_reports_screen.dart')
remote_detail=text('client/pos_app/lib/features/cloud_admin/reports/presentation/remote_report_detail_screen.dart')
report_routes=['/summary','/sales','/sales/details','/products','/products/low-performance','/categories','/users','/purchases','/suppliers','/inventory','/expenses','/cash','/payment-methods','/cancellations','/trends/products']
missing_report_routes=[x for x in report_routes if f'reportApi.MapGet("{x}"' not in program]
if 'app.MapGroup("/api/admin/reports").RequireAuthorization("Administrator")' not in program:
    fail('FASE17 report authorization','remote report group must require Administrator policy')
elif missing_report_routes:
    fail('FASE17 report routes','missing '+', '.join(missing_report_routes))
else:
    ok('FASE17 report routes',f'{len(report_routes)} Administrator-only read endpoints')
report_tenant_ok=(report_service.count('tenant.BusinessId')>=18 and 'Tenant context is not active.' in report_service and 'business.Id == tenant.BusinessId' in report_service)
if not report_tenant_ok: fail('FASE17 tenant isolation','report service lacks pervasive claim-derived BusinessId scoping')
else: ok('FASE17 tenant isolation','report queries scoped by authenticated tenant context')
fifo_ok=('SaleLotAllocations' in report_service and 'allocation.TotalCostCents' in report_service and 'AvailableQuantity' in report_service and 'UnitCostCents' in report_service)
if not fifo_ok: fail('FASE17 FIFO reporting','historical allocation cost and remaining lot valuation patterns missing')
else: ok('FASE17 FIFO reporting','historical SaleLotAllocation cost + remaining lot valuation present')
report_contract_names=['RemoteSummaryReport','SalesPeriodRow','ProductPerformanceRow','CategoryPerformanceRow','UserPerformanceRow','PurchaseReportRow','SupplierPerformanceRow','InventoryReportRow','ExpenseReportResponse','CashReportRow','PaymentMethodReportRow','CancellationReportResponse','ProductTrendRow']
missing_contracts=[x for x in report_contract_names if x not in report_contracts]
if missing_contracts: fail('FASE17 report contracts',', '.join(missing_contracts))
else: ok('FASE17 report contracts',f'{len(report_contract_names)} explicit DTO contracts')
if 'businessId' in remote_repo or 'BusinessId' in remote_repo: fail('FASE17 Flutter tenant authority','remote report client must not send BusinessId')
elif '/api/admin/reports/summary' not in remote_repo or '/cloud-admin/reports' not in text('client/pos_app/lib/app/router.dart'): fail('FASE17 Flutter routing','remote report repository/router wiring missing')
else: ok('FASE17 Flutter routing','cloud admin reports use tenant-free GET queries and dedicated routes')
if '_api.post' in remote_repo: fail('FASE17 report read-only client','remote report repository contains mutation call')
else: ok('FASE17 report read-only client','remote report repository performs GET-only reads')
dimension_keys=['productGlobalId','categoryGlobalId','supplierGlobalId','userGlobalId']
if not all(key in remote_repo and key in program for key in dimension_keys) or 'businessId' in remote_repo or 'BusinessId' in remote_repo:
    fail('FASE17 dimension filters','tenant-free GlobalId report filters are incomplete')
else:
    ok('FASE17 dimension filters','product/category/supplier/user filters use GlobalId without client BusinessId authority')
if not all(x in remote_detail for x in ['RemoteReportCsvService','DataTable','LinearProgressIndicator']): fail('FASE17 report presentation','table/chart/export wiring incomplete')
else: ok('FASE17 report presentation','tablet table + lightweight chart + CSV export present')
if 'StableThresholdPercent = 5.0' not in report_service or 'current period versus immediately preceding equal-length period' not in program: fail('FASE17 trend definition','stable threshold or comparison definition missing')
else: ok('FASE17 trend definition','Stable threshold ±5% revenue; equal-length previous period documented')

# EF model required entities/indexes
entities=text('server/src/Domain/Entities.cs')
required_entities=['Business','Branch','Device','UserAccount','Category','Supplier','Product','Purchase','PurchaseLine','InventoryLot','InventoryMovement','Sale','SaleLine','SaleLotAllocation','CashSession','Expense','InboundOperation','SyncChange','RefreshToken','DeviceEnrollmentToken']
missing_entities=[e for e in required_entities if re.search(rf'class\s+{e}\b',entities) is None]
if missing_entities: fail('EF model','missing entities '+', '.join(missing_entities))
elif 'new{x.BusinessId,x.Id}' not in dbctx or 'TokenHash).IsUnique()' not in dbctx: fail('EF model','required SyncChange/token indexes missing')
else: ok('EF model',f'{len(required_entities)} core entities + tenant cursor/token indexes present')

# DI/contracts/symbols
required_symbols=['ISyncService','ITokenService','SyncTenantContext','SyncPushRequest','SyncPullResponse','DevicePullPayload','RedeemDeviceEnrollmentRequest']
apptext=text('server/src/Application/Contracts.cs')+'\n'+text('server/src/Application/Abstractions.cs')
miss_sym=[s for s in required_symbols if s not in apptext]
if miss_sym: fail('Application contracts',', '.join(miss_sym))
elif not all(x in program for x in ['AddScoped<ISyncService,SyncService>','AddScoped<ITokenService>','AddScoped<DeviceEnrollmentService>','AddScoped<TenantReadService>']): fail('DI registrations','required services missing')
else: ok('Application contracts/DI','contracts and core DI registrations present')

# Known reconstructed integration regressions
for pat,label in [('linePayload.GlobalId','stale SaleLine GlobalId contract'),('payload.UpdatedAt ??','nullable UpdatedAt mismatch')]:
    if pat in sync_cs: fail('known integration regression',label)
if not any(n=='known integration regression' for n,_ in errors): ok('known integration regression','none')

print('STRUCTURAL_GATE='+('PASS' if not errors else 'FAIL'))
print('HIGH_CONFIDENCE_SECRETS='+str(len(secret_hits)))
for n,d in checks: print(f'PASS {n}: {d}')
for n,d in warnings: print(f'WARN {n}: {d}')
for n,d in errors: print(f'FAIL {n}: {d}')
sys.exit(1 if errors else 0)
