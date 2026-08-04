import Foundation
@testable import TimeOfLife

/// A fake `RemoteEntriesRepository` for testing the `SyncCoordinator`.
/// Records all calls and returns canned results/errors per endpoint.
/// `@MainActor` for safe synchronous access to recorded state in tests.
@MainActor
final class FakeEntriesRepository: EntriesRemoteSending {

    private(set) var listEntriesCalls = 0
    private(set) var listAllEntriesCalls = 0
    private(set) var createEntryCalls: [EntryCreateRequest] = []
    private(set) var updateEntryCalls: [(id: String, request: EntryUpdateRequest)] = []
    private(set) var deleteEntryCalls: [String] = []
    private(set) var getEntryCalls: [String] = []

    var listEntriesResult: EntryListResponseDTO = .init(items: [], nextCursor: nil)
    var listEntriesError: Error?

    var createEntryResult: ((EntryCreateRequest) -> EntryDTO?)?
    var createEntryError: ((EntryCreateRequest) -> Error?)?

    var updateEntryResult: ((String, EntryUpdateRequest) -> EntryDTO?)?
    var updateEntryError: ((String, EntryUpdateRequest) -> Error?)?

    var deleteEntryError: ((String) -> Error?)?

    var getEntryResult: ((String) -> EntryDTO?)?
    var getEntryError: ((String) -> Error?)?

    func reset() {
        listEntriesCalls = 0
        listAllEntriesCalls = 0
        createEntryCalls = []
        updateEntryCalls = []
        deleteEntryCalls = []
        getEntryCalls = []
        listEntriesResult = EntryListResponseDTO(items: [], nextCursor: nil)
        listEntriesError = nil
        createEntryResult = nil
        createEntryError = nil
        updateEntryResult = nil
        updateEntryError = nil
        deleteEntryError = nil
        getEntryResult = nil
        getEntryError = nil
    }
}

extension FakeEntriesRepository {
    func listEntries(cursor: String? = nil, limit: Int = 100) async throws -> EntryListResponseDTO {
        listEntriesCalls += 1
        if let listEntriesError { throw listEntriesError }
        return listEntriesResult
    }

    func listAllEntries() async throws -> [EntryDTO] {
        listAllEntriesCalls += 1
        if let listEntriesError { throw listEntriesError }
        return listEntriesResult.items
    }

    func createEntry(_ request: EntryCreateRequest) async throws -> EntryDTO {
        createEntryCalls.append(request)
        if let error = createEntryError?(request) { throw error }
        if let result = createEntryResult?(request) { return result }
        return EntryDTO(id: request.id, activityId: request.activityId,
                        activityName: "Activity", startedAt: request.startedAt,
                        endedAt: request.endedAt, durationSeconds: nil,
                        createdAt: Date(), updatedAt: Date(), categories: [])
    }

    func updateEntry(id: String, request: EntryUpdateRequest) async throws -> EntryDTO {
        updateEntryCalls.append((id, request))
        if let error = updateEntryError?(id, request) { throw error }
        if let result = updateEntryResult?(id, request) { return result }
        return EntryDTO(id: id, activityId: "act-1", activityName: "Activity",
                        startedAt: request.startedAt ?? Date(),
                        endedAt: request.endedAt, durationSeconds: nil,
                        createdAt: Date(), updatedAt: request.updatedAt, categories: [])
    }

    func deleteEntry(id: String) async throws {
        deleteEntryCalls.append(id)
        if let error = deleteEntryError?(id) { throw error }
    }

    func getEntry(id: String) async throws -> EntryDTO {
        getEntryCalls.append(id)
        if let error = getEntryError?(id) { throw error }
        if let result = getEntryResult?(id) { return result }
        return EntryDTO(id: id, activityId: "act-1", activityName: "Activity",
                        startedAt: Date(), endedAt: nil, durationSeconds: nil,
                        createdAt: Date(), updatedAt: Date(), categories: [])
    }
}
