import Testing
import Foundation
@testable import TimeOfLife

/// Gap-coverage for the complexity-reduction slice (tasks 3.x + 4.2).
@MainActor
@Suite("ComplexitySlice")
struct ComplexitySliceTests {

    // MARK: - ExactName (task 3.1)

    @Test("ExactName maps the store DTO")
    func exactNameMapsStoreDTO() {
        let dto = RecentEntry(activityText: "Gym", categoryIDs: ["c1", "c2"], startedAt: Date())
        let name = ExactName(storeRecent: dto)
        #expect(name.text == "Gym")
        #expect(name.categoryIDs == ["c1", "c2"])
        #expect(name.firstCategoryID == "c1")
        #expect(name.id == "Gym")
    }

    @Test("ExactName defaults the icon source to the first category")
    func exactNameDefaultsFirstCategory() {
        let named = ExactName(text: "Run", categoryIDs: ["c9"])
        #expect(named.firstCategoryID == "c9")
        let bare = ExactName(text: "Idle", categoryIDs: [])
        #expect(bare.firstCategoryID == nil)
    }

    // MARK: - DurationFormatting centralization (task 3.2)

    @Test("clock grammar matches the legacy TimeFormatter entry point")
    func clockMatchesLegacy() {
        for sample in [0.0, 5.0, 125.0, 3661.0, 36000.0] {
            #expect(DurationFormatting.clock(sample) == TimeFormatter.formattedDuration(sample))
        }
        #expect(DurationFormatting.clock(125) == "02:05")
        #expect(DurationFormatting.clock(3661) == "1:01:01")
    }

    @Test("natural grammar matches the HistoryViewModel entry point")
    func naturalMatchesLegacy() {
        let locale = Locale(identifier: "en")
        for sample in [0, 33, 90, 3720, 90000] {
            #expect(DurationFormatting.natural(sample, locale: locale)
                == HistoryViewModel.naturalDuration(sample, locale: locale))
        }
    }

    @Test("focus settle preserves the 400ms transition constant")
    func focusDelayConstant() {
        #expect(FocusDelay.settleNanoseconds == 400_000_000)
    }

    // MARK: - SessionCache edges (task 4.2)

    @Test("fresh defaults load no session")
    func sessionCacheFreshLoadsNil() {
        let cache = SessionCache(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        #expect(cache.load() == nil)
    }

    @Test("save then clear round-trips through load")
    func sessionCacheSaveClear() {
        let cache = SessionCache(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let session = CachedSession(id: "u1", email: "a@b.com", emailVerified: true)
        cache.save(session)
        #expect(cache.load() == session)
        cache.clear()
        #expect(cache.load() == nil)
    }

    @Test("partial data (id without email) loads nil")
    func sessionCachePartialLoadsNil() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set("u1", forKey: "com.timeoflife.session.id")
        let cache = SessionCache(defaults: defaults)
        #expect(cache.load() == nil)
    }

    // MARK: - Connectivity double (task 4.2)

    @Test("base connectivity is connected; the mock drives the flag")
    func connectivityDefaults() {
        #expect(Connectivity().isConnected)
        let mock = MockConnectivity(connected: false)
        #expect(!mock.isConnected)
        mock.isConnected = true
        #expect(mock.isConnected)
    }

    // MARK: - AppContainer open/close/erase scope (tasks 3.4, 4.2)

    @Test("openLocalStore binds a fresh account")
    func openBindsFreshAccount() async {
        let container = makeContainer()
        let userID = uniqueUserID()
        defer { removeAccountFile(userID: userID) }

        let opened = await container.openLocalStore(userID: userID)

        #expect(opened)
        #expect(container.localStoreOpenError == nil)
        #expect(await container.localStore.boundUserID == userID)
        #expect((try? await container.localStore.categories()) != nil)
    }

    @Test("invalid user surfaces error")
    func invalidUserSurfacesError() async {
        let container = makeContainer()

        let opened = await container.openLocalStore(userID: "not valid!!")

        // Integrity failure, surfaced — never a crash: the store stays
        // cleanly unbound and the gate stays up with the error.
        #expect(!opened)
        #expect(container.localStoreOpenError != nil)
        #expect(await container.localStore.boundUserID == nil)
        await #expect(throws: LocalStore.LocalStoreError.notBound) {
            try await container.localStore.categories()
        }
    }

    @Test("closeLocalStore unbinds but keeps the file for re-login")
    func closeUnbindsKeepsFile() async throws {
        let container = makeContainer()
        let userID = uniqueUserID()
        defer { removeAccountFile(userID: userID) }
        _ = await container.openLocalStore(userID: userID)
        try await container.localStore.createEntry(makeEntry(id: "e1", text: "Gym"))

        await container.closeLocalStore()

        #expect(await container.localStore.boundUserID == nil)
        await #expect(throws: LocalStore.LocalStoreError.notBound) {
            try await container.localStore.categories()
        }
        #expect(FileManager.default.fileExists(atPath: LocalStore.databaseURL(userID: userID).path))
    }

    @Test("rapid re-login to the same account resumes its outbox")
    func rapidReloginResumesOutbox() async throws {
        let container = makeContainer()
        let userID = uniqueUserID()
        defer { removeAccountFile(userID: userID) }
        _ = await container.openLocalStore(userID: userID)
        try await container.localStore.createEntry(makeEntry(id: "e1", text: "Gym"))
        await container.closeLocalStore()

        let reopened = await container.openLocalStore(userID: userID)

        #expect(reopened)
        let rows = try await container.localStore.outboxRows()
        #expect(rows.contains { $0.recordID == "e1" && $0.op == "create" })
    }

    @Test("eraseLocalData removes only the active account file")
    func eraseRemovesOnlyActiveFile() async throws {
        let container = makeContainer()
        let userA = uniqueUserID()
        let userB = uniqueUserID()
        defer {
            removeAccountFile(userID: userA)
            removeAccountFile(userID: userB)
        }
        _ = await container.openLocalStore(userID: userA)
        try await container.localStore.createEntry(makeEntry(id: "ea", text: "A-entry"))
        await container.closeLocalStore()
        _ = await container.openLocalStore(userID: userB)
        try await container.localStore.createEntry(makeEntry(id: "eb", text: "B-entry"))

        try await container.eraseLocalData()

        #expect(await container.localStore.boundUserID == nil)
        #expect(!FileManager.default.fileExists(atPath: LocalStore.databaseURL(userID: userB).path))
        #expect(FileManager.default.fileExists(atPath: LocalStore.databaseURL(userID: userA).path))
        _ = await container.openLocalStore(userID: userA)
        #expect((try? await container.localStore.entry(id: "ea"))?.activityText == "A-entry")
    }

    // MARK: - Publisher-based shutdown wait (tasks 3.3, 4.2)

    @Test("waitForCycleEnd returns at once when no cycle is live")
    func shutdownWaitImmediateWhenIdle() async {
        let (_, _, controller) = makeSyncContext()
        #expect(!controller.isCycleLive)
        await controller.waitForCycleEnd(timeout: 2)
        #expect(!controller.isCycleLive)
    }

    @Test("waitForCycleEnd waits for the in-flight cycle")
    func shutdownWaitFollowsLiveCycle() async throws {
        let (store, mock, controller) = makeSyncContext()
        try await store.createEntry(makeEntry(id: "e1", text: "Gym"))
        mock.createEntryHandler = { _ in
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        controller.activate(userID: "u1")
        #expect(controller.isCycleLive)

        let start = Date()
        await controller.waitForCycleEnd(timeout: 5)
        let elapsed = Date().timeIntervalSince(start)

        #expect(elapsed >= 0.25, "returned before the held cycle ended")
        #expect(!controller.isCycleLive)
        if case .idle = controller.status {} else {
            Issue.record("expected idle after the cycle, got \(controller.status)")
        }
    }

    @Test("waitForCycleEnd is bounded by its timeout")
    func shutdownWaitBoundedByTimeout() async throws {
        let (store, mock, controller) = makeSyncContext()
        try await store.createEntry(makeEntry(id: "e1", text: "Gym"))
        mock.createEntryHandler = { _ in
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        controller.activate(userID: "u1")

        let start = Date()
        await controller.waitForCycleEnd(timeout: 0.2)
        let elapsed = Date().timeIntervalSince(start)

        #expect(elapsed >= 0.15, "did not honor the live-cycle wait")
        #expect(elapsed < 1.5, "exceeded the shutdown deadline")
        controller.deactivate()
        await controller.waitForCycleEnd(timeout: 2)
        #expect(!controller.isCycleLive)
    }

    // MARK: - Track external-stop and state guards (task 4.2)

    @Test("load reconciles an externally stopped timer with text to ready")
    func externalStopWithTextReturnsToReady() async {
        let vm = makeTrackViewModel()
        vm.state = .running(TrackState.Draft(text: "Gym", categoryIDs: ["c1"]), startedAt: Date())

        await vm.load()

        #expect(vm.state == .ready(TrackState.Draft(text: "Gym", categoryIDs: ["c1"])))
        #expect(vm.elapsed == 0)
    }

    @Test("load reconciles an externally stopped timer with empty text to idle")
    func externalStopEmptyReturnsToIdle() async {
        let vm = makeTrackViewModel()
        vm.state = .running(TrackState.Draft(text: ""), startedAt: Date())

        await vm.load()

        #expect(vm.state == .idle)
        #expect(vm.elapsed == 0)
    }

    @Test("chip selection while running is ignored")
    func selectWhileRunningIgnored() {
        let vm = makeTrackViewModel()
        vm.state = .running(
            TrackState.Draft(text: "Gym", categoryIDs: ["c1"]),
            startedAt: Date()
        )
        vm.nameDraft = "Gym"

        vm.select(ExactName(text: "Yoga", categoryIDs: ["c2"], firstCategoryID: "c2"))

        guard case let .running(draft, _) = vm.state else {
            Issue.record("expected running state to survive a chip tap, got \(vm.state)")
            return
        }
        #expect(draft.text == "Gym")
        #expect(draft.categoryIDs == ["c1"])
        #expect(vm.nameDraft == "Gym")
    }

    @Test("stop, retryStop, and toggleDraftCategory are no-ops outside their states")
    func guardsOutsideStates() async {
        let vm = makeTrackViewModel()

        await vm.stop()
        #expect(vm.state == .idle)
        await vm.retryStop()
        #expect(vm.state == .idle)
        vm.toggleDraftCategory("c1")
        #expect(vm.state == .idle)
    }

    // MARK: - History reload gate (task 4.2)

    @Test("concurrent loadIfNeeded calls serialize")
    func concurrentLoadIfNeededSerializes() async throws {
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        try await store.createEntry(makeEntry(
            id: "e1", text: "Gym",
            startedAt: Date().addingTimeInterval(-3_600),
            duration: 60
        ))
        let vm = HistoryViewModel(store: store)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask { await vm.loadIfNeeded() }
            }
            await group.waitForAll()
        }

        #expect(vm.dayGroups.count == 1)
        #expect(vm.dayGroups.first?.entries.map(\.id) == ["e1"])
    }

    private func uniqueUserID() -> String { "cx-" + UUID().uuidString.lowercased() }

    private func removeAccountFile(userID: String) {
        let url = LocalStore.databaseURL(userID: userID)
        try? FileManager.default.removeItem(at: url)
        for ext in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + ext))
        }
    }

    private func makeEntry(
        id: String,
        text: String,
        categoryIDs: [String] = [],
        startedAt: Date = Date(),
        duration: Int = 60
    ) -> TimeEntry {
        TimeEntry(
            id: id,
            activityText: text,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(TimeInterval(duration)),
            durationSeconds: duration,
            source: "manual",
            categoryIDs: categoryIDs
        )
    }

    private func makeTrackViewModel() -> TrackViewModel {
        let connectivity = MockConnectivity(connected: true)
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        return TrackViewModel(service: TimerService(store: store), connectivity: connectivity)
    }

    private func temporaryStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(LocalStore.databaseFileName(userID: "u1"))
    }

    private func makeContainer() -> AppContainer {
        let url = URL(string: "https://example.com")!
        let repository = FakeAuthRepository()
        let keychain = InMemoryKeychainStore()
        let cache = SessionCache(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let sessionStore = SessionStore()
        let localStore = LocalStore()
        let connectivity = MockConnectivity(connected: true)
        let authService = AuthService(repository: repository, keychain: keychain, cache: cache, sessionStore: sessionStore)
        return AppContainer(
            baseURL: url,
            apiClient: APIClient(baseURL: url, session: .shared),
            keychain: keychain,
            sessionCache: cache,
            repository: repository,
            sessionStore: sessionStore,
            navigation: AppNavigationStack(),
            connectivity: connectivity,
            authService: authService,
            appleService: AppleSignInService(),
            timerService: TimerService(store: localStore),
            localStore: localStore,
            undoBuffer: UndoBufferStore(store: localStore),
            syncController: SyncController(
                store: localStore,
                remote: MockCatalogRepository(),
                connectivity: connectivity
            ) { nil }
        )
    }

    private func makeSyncContext() -> (
        store: LocalStore, mock: MockCatalogRepository, controller: SyncController
    ) {
        // swiftlint:disable:next force_try
        let store = try! LocalStore(url: temporaryStoreURL())
        let mock = MockCatalogRepository()
        let controller = SyncController(
            store: store,
            remote: mock,
            connectivity: MockConnectivity(connected: true)
        ) { "u1" }
        return (store, mock, controller)
    }
}
