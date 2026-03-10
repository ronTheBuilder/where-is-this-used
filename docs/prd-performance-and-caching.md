# PRD: Performance & Caching — Query Optimization and Result Caching

**Version**: 1.0
**Date**: 2026-02-17
**Parent**: Where Is This Used? (WITU)
**Status**: Draft

---

## 1. Problem Statement

WITU v1 queries the Tooling API fresh every time, with no caching. For frequently-searched components or in orgs with slow networks, users experience delays:

- **Repeated searches** — An admin searches `Account.Industry` 3 times in one session. Each search queries the Tooling API again (20-30 second wait each time).
- **Dependent queries** — Blast Radius queries the same component multiple times at different depths. Each level re-queries MetadataComponentDependency.
- **Subflow detection** — For every Flow found, the system retrieves Flow metadata to detect subflows. 100 Flows = 100 API calls just to check for subflows.
- **Network latency** — Orgs with poor network connectivity experience 15-30 second waits per search.
- **Rate limiting** — High query volume risks hitting Tooling API rate limits (200 concurrent requests per org).

### Real-World Scenarios

| Scenario | Current Pain |
|----------|-------------|
| Admin explores field dependencies while on a call | Searches `Account.Industry`, finds 10 Flows, clicks one of them to search for its dependencies. Same query runs again → 20 second wait. |
| Developer runs Blast Radius twice to compare different depth settings | Blast Radius depth 2 queries 50 components. Blast Radius depth 3 queries many of the same components again + new ones. Redundant queries. |
| Large org with 500+ active Flows | Subflow detection queries 500 flows for metadata. Each query is 1 API call = 500 calls total. Session hits rate limit. |
| Team of 10 admins searches the same high-use field | 10 searches of `Account.Name` = 10 identical Tooling API queries when 1 would suffice. |

## 2. Solution

Three-tier caching strategy:

### 2.1 Session Cache (Default)
- **Scope**: Current user session (8-hour TTL)
- **Store**: `Platform.Cache.Session` — built-in LWC cache, org-wide quota shared by all orgs
- **When to use**: Safe for per-user searches that won't change during a session
- **Hit scenario**: Admin searches `Account.Industry` twice → second search uses cache (instant)

### 2.2 Org Cache (Opt-In)
- **Scope**: Entire org, all users (24-hour TTL)
- **Store**: `Platform.Cache.Org` — org-wide, shared by all users
- **When to use**: Stable metadata that rarely changes (Apex classes, Flows, VRs)
- **Hit scenario**: Admin 1 searches `MyFlow`, admin 2 searches `MyFlow` 5 minutes later → uses cached result from admin 1

### 2.3 Query Optimization
- **Subflow detection batching**: Instead of 1 API call per flow, batch metadata retrievals
- **Blast Radius graph reuse**: When traversing at depth 3, reuse depth 2 results already computed
- **Client-side filtering optimization**: Already filters by `RefMetadataComponentName` client-side; no further optimization

## 3. Technical Architecture

### 3.1 Session Cache Implementation

**Using**: `Platform.Cache.Session` (LightningComponent in controller)

```apex
public class DependencyService {
    private static final String CACHE_PARTITION = 'WITU';
    private static final Integer CACHE_TTL_SECONDS = 28800; // 8 hours

    private static String makeCacheKey(String metadataType, String componentName) {
        return 'WITU:' + metadataType + ':' + componentName;
    }

    public static DependencySearchResponse searchDependencies(
        String metadataType, String componentName
    ) {
        enforceAccess();
        validateInputs(metadataType, componentName);

        String cacheKey = makeCacheKey(metadataType, componentName);
        DependencySearchResponse cached = (DependencySearchResponse) Cache.Session.get(cacheKey);
        if (cached != null) {
            return cached;
        }

        // Execute query (existing logic)
        DependencySearchResponse result = queryDependencies(metadataType, componentName);

        // Store in cache
        try {
            Cache.Session.put(cacheKey, result, CACHE_TTL_SECONDS);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Failed to cache result: ' + e.getMessage());
            // Fail silently — cache miss is not critical
        }

        return result;
    }
}
```

**Pros**:
- No setup required — enabled by default
- Per-user (no stale data seen by other users)
- 8-hour TTL good for typical session duration

**Cons**:
- User A's result not available to User B
- Cache miss = slower than org cache
- Org cache quota shared across all Lightning features

### 3.2 Org Cache Implementation

**Using**: `Platform.Cache.Org` (requires manual enable)

```apex
public class DependencyService {
    private static final String ORG_CACHE_PARTITION = 'WITU_Org';
    private static final Integer ORG_CACHE_TTL_SECONDS = 86400; // 24 hours

    @AuraEnabled
    public static void setCacheMode(String mode) {
        // mode: 'session' (default) or 'org'
        // Store user preference in User record or custom setting
        FeatureFlag.setUserPreference('WITU_CacheMode', mode);
    }

    public static DependencySearchResponse searchDependencies(
        String metadataType, String componentName
    ) {
        enforceAccess();
        validateInputs(metadataType, componentName);

        String cacheMode = FeatureFlag.getUserPreference('WITU_CacheMode', 'session');
        String cacheKey = makeCacheKey(metadataType, componentName);

        // Try session cache first (faster)
        DependencySearchResponse cached = (DependencySearchResponse) Cache.Session.get(cacheKey);
        if (cached != null) {
            return cached;
        }

        // Try org cache if enabled
        if (cacheMode == 'org') {
            try {
                cached = (DependencySearchResponse) Cache.Org.get(ORG_CACHE_PARTITION, cacheKey);
                if (cached != null) {
                    // Populate session cache for this user for next access
                    Cache.Session.put(cacheKey, cached, CACHE_TTL_SECONDS);
                    return cached;
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Org cache read failed: ' + e.getMessage());
            }
        }

        // Execute query
        DependencySearchResponse result = queryDependencies(metadataType, componentName);

        // Store in both caches
        try {
            Cache.Session.put(cacheKey, result, CACHE_TTL_SECONDS);
            if (cacheMode == 'org') {
                Cache.Org.put(ORG_CACHE_PARTITION, cacheKey, result, ORG_CACHE_TTL_SECONDS);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Cache write failed: ' + e.getMessage());
        }

        return result;
    }
}
```

**Prerequisites**:
- Setup → Platform Cache → Create a cache partition named `WITU_Org` (org cache shared across all WITU instances)
- Partition allocation: 1-10 MB (configurable). Start with 1 MB.

**Pros**:
- Shared across all users (admin 1 searches `MyFlow`, admin 2 gets instant result)
- 24-hour TTL good for stable metadata

**Cons**:
- Requires org admin setup (not automatic)
- Cache size limited (1-10 MB) — depends on result size and volume
- May show stale data if metadata changes and cache not invalidated

### 3.3 Cache Invalidation

Manual invalidation via @AuraEnabled method:

```apex
@AuraEnabled
public static void invalidateCache(String metadataType, String componentName) {
    enforceAccess();
    String cacheKey = makeCacheKey(metadataType, componentName);
    try {
        Cache.Session.remove(cacheKey);
        Cache.Org.remove('WITU_Org', cacheKey);
    } catch (Exception e) {
        System.debug(LoggingLevel.WARN, 'Cache invalidation failed: ' + e.getMessage());
    }
}

@AuraEnabled
public static void clearAllCache() {
    enforceAccess();
    if (!FeatureManagement.checkPermission('WITU_Admin')) {
        throw new DependencyServiceException('Only admins can clear org cache.');
    }
    try {
        Cache.Session.remove('*'); // Clear all session keys
        // Org cache: cannot clear all at once — requires partition clear (admin operation)
    } catch (Exception e) {
        System.debug(LoggingLevel.WARN, 'Cache clear failed: ' + e.getMessage());
    }
}
```

**UI button**: "Clear Cache" button in Setup tab for admins. Clears org and session caches.

### 3.4 Subflow Detection Optimization

**Current**: For each Flow found, 1 API call to `/tooling/sobjects/Flow/{id}` to get metadata.

**Optimized**: Batch metadata retrievals where possible.

```apex
// Current approach — 100 flows = 100 calls:
List<FlowVersionView> flows = queryActiveFlows(); // 1 call
for (ActiveFlowVersion flow : flows) {
    FlowFieldAnalyzer.FlowFieldAnalysis analysis = getFlowAnalysisByVersionId(flow.id);
    // getFlowAnalysisByVersionId() makes 1 callout per flow
}

// Optimized approach — 100 flows = ~4-5 calls with batch:
List<FlowVersionView> flows = queryActiveFlows(); // 1 call
Map<String, FlowFieldAnalyzer.FlowFieldAnalysis> cachedAnalysis = new Map<>();
for (ActiveFlowVersion flow : flows) {
    String cacheKey = 'Flow:' + flow.id;
    FlowFieldAnalyzer.FlowFieldAnalysis cached =
        (FlowFieldAnalyzer.FlowFieldAnalysis) Cache.Session.get(cacheKey);
    if (cached != null) {
        cachedAnalysis.put(flow.id, cached);
        continue;
    }

    // Batch metadata retrieval (if API supports batch — Tooling API does not natively)
    // Fallback: retrieve metadata one at a time but cache each result
    HttpResponse response = sendGet(TOOLING_BASE_PATH + '/sobjects/Flow/' + flow.id);
    FlowFieldAnalyzer.FlowFieldAnalysis analysis =
        FlowFieldAnalyzer.analyzeFlow(parseMetadata(response.getBody()));

    // Cache the analysis
    Cache.Session.put(cacheKey, analysis, CACHE_TTL_SECONDS);
    cachedAnalysis.put(flow.id, analysis);
}
```

**Result**: For repeated subflow detection in the same session (e.g., multiple blast radius queries), metadata lookups hit session cache → zero additional API calls.

### 3.5 Blast Radius Graph Reuse

**Current**: Each Blast Radius query independently traverses the full graph.

**Optimized**: When querying depth 3 after depth 2, reuse cached depth 2 result as starting point.

```apex
public static BlastRadiusResponse getBlastRadius(
    String metadataType, String componentName, Integer maxDepth
) {
    enforceAccess();
    validateInputs(metadataType, componentName);

    // Check if a deeper cached result exists
    for (int cachedDepth = maxDepth; cachedDepth >= 1; cachedDepth--) {
        String cacheKey = 'BR:' + metadataType + ':' + componentName + ':' + cachedDepth;
        BlastRadiusResponse cached = (BlastRadiusResponse) Cache.Session.get(cacheKey);
        if (cached != null && cached.totalDepth >= maxDepth) {
            return cached; // Reuse exact cached result
        }
        if (cached != null && cached.totalDepth >= maxDepth - 1) {
            // Reuse partial result, extend by 1 level
            return extendGraph(cached, maxDepth);
        }
    }

    // Compute new graph
    BlastRadiusResponse result = computeBlastRadius(metadataType, componentName, maxDepth);

    // Cache by depth
    String cacheKey = 'BR:' + metadataType + ':' + componentName + ':' + maxDepth;
    Cache.Session.put(cacheKey, result, CACHE_TTL_SECONDS);

    return result;
}

private static BlastRadiusResponse extendGraph(BlastRadiusResponse partial, Integer newDepth) {
    // Starting from partial result at depth N, traverse only new nodes at depth N+1
    // Reuses nodes already computed
    // Cost: ~1 API call per new level instead of recomputing entire graph
}
```

**Result**: User adjusts Blast Radius depth from 2 → 3 → 2 → 3. Second depth-3 query instant (cache hit). Depth adjustments are fast.

## 4. UI Design

### Cache Settings (Setup Tab)

```
┌─────────────────────────────────────────────────┐
│  Performance Settings                           │
├─────────────────────────────────────────────────┤
│                                                 │
│  Cache Mode:                                    │
│  ⦿ Session Cache (Recommended)                  │
│    Results cached for your session only (8hrs)  │
│  ○ Org Cache (Requires Setup)                   │
│    Results cached org-wide (24hrs, shared)      │
│                                                 │
│  Current Cache Size:                            │
│  Session: 42 KB / 5 MB                          │
│  Org: 128 KB / 1 MB                             │
│                                                 │
│  [Clear Session Cache]  [Clear Org Cache]       │
│  (Org cache only available to admins)           │
│                                                 │
│  Recent Searches (Cached):                      │
│  • Account.Industry                 [Clear]     │
│  • Route_By_Industry                [Clear]     │
│  • AccountService                   [Clear]     │
│                                                 │
│  Cache Hit Rate (Session):                      │
│  12 of 34 searches (35%) from cache             │
│  Avg Response Time: 0.2s (cache) vs 15s (fresh) │
│                                                 │
└─────────────────────────────────────────────────┘
```

### Cache Status in Results

```
Showing results for Account.Industry    [Standard Field]
◻ (from cache, 15 seconds old)    [Refresh]

23 references found
```

## 5. Files to Create / Modify

### Modified Files

| File | Change |
|------|--------|
| `DependencyService.cls` | Add session/org cache logic. Add cache key generation. Wrap query in cache get/put. Add `invalidateCache()` and `clearAllCache()` methods. |
| `DependencyServiceTest.cls` | Add tests for cache hits/misses. Mock Platform.Cache. |
| `BlastRadiusService.cls` | Add blast radius graph caching. Implement `extendGraph()` for depth reuse. |
| `BlastRadiusServiceTest.cls` | Test graph extension and caching. |
| `DataJourneyService.cls` | Add session cache for data journey results. |
| `setupWizard` LWC | Add "Performance Settings" section showing cache mode, size, hit rate. Add cache management buttons. |
| `DependencyController.cls` | Add `@AuraEnabled setCacheMode()` and `clearAllCache()` methods. |

### New Custom Settings (Optional)

| Custom Setting | Field | Purpose |
|----------------|-------|---------|
| `WITU_CacheConfig__c` | `CacheMode__c` | 'session' or 'org' |
| `WITU_CacheConfig__c` | `SessionCacheTTL__c` | TTL in seconds (default 28800) |
| `WITU_CacheConfig__c` | `OrgCacheTTL__c` | TTL in seconds (default 86400) |

## 6. Platform Cache Setup (Admin Manual Step)

Before enabling Org Cache, admin must:

1. **Create partition**: Setup → Platform Cache → Create New Partition
   - Name: `WITU_Org`
   - Allocation: 1 MB
   - Org Cache (shared by all users)

2. **Verify quota**: Setup → Platform Cache → Monitor
   - Org cache quota: 10 MB per org
   - WITU_Org takes 1 MB (10% of quota)

## 7. API Budget Impact

| Strategy | API Calls Saved |
|----------|-----------------|
| Session Cache hit (repeat search) | 1-2 calls per hit |
| Org Cache hit (different user, same search) | 1-2 calls per hit |
| Subflow metadata caching | 90%+ reduction for 100+ Flows in same session |
| Blast Radius graph reuse | ~1 call per level instead of full recomputation |
| Combined impact (active session) | 40-60% reduction in API calls |

## 8. Known Limitations

| Limitation | Impact | Mitigation |
|-----------|--------|-----------|
| Session cache not shared across browser tabs | User opens same page in 2 tabs → separate caches | Acceptable — tabs are independent sessions |
| Org cache size limit (1-10 MB) | Large result sets (1000+ dependencies) may not fit | Monitor cache size in UI, allow admin to allocate more |
| 24-hour TTL means stale data possible | Metadata added/modified overnight not reflected until cache expires | Manual "Refresh" button and cache clear available |
| Subflow metadata cached but Flow definition may change | If Flow logic changes, old analysis still served | 24-hour TTL acceptable for most use cases |

## 9. AppExchange Considerations

- Cache operations wrapped in try-catch — cache failures don't break core functionality
- No external storage — all caching uses built-in Platform Cache APIs
- WITU_Admin custom permission required for org cache clear
- Test coverage: mock Platform.Cache in unit tests, verify get/put/remove logic

## 10. Success Metrics

| Metric | Target |
|--------|--------|
| Session cache hit rate | 40%+ of searches in active session |
| Org cache adoption | 50%+ of orgs enable org cache after setup |
| API call reduction (session cache) | 30-40% fewer Tooling API calls |
| API call reduction (org cache) | 60-70% fewer Tooling API calls across org |
| Avg response time (cache hit) | < 500ms (from <15s) |
| Subflow detection speedup | 90%+ faster on repeat queries |
| Blast Radius depth adjustment | Instant (< 1s) when reusing cached result |
| Cache miss rate monitoring | Alert admin if hit rate falls below 20% |
