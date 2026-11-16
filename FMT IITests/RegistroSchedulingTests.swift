import XCTest
import BackgroundTasks
@testable import FMT_II

@MainActor
final class RegistroSchedulingTests: XCTestCase {
    private var defaults: UserDefaults!
    private var dir: URL!

    override func setUpWithError() throws {
        defaults = UserDefaults(suiteName: "RegistroSchedulingTests-\(UUID().uuidString)")
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("RegistroSchedulingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeCoordinator() -> RegistroSyncCoordinator {
        let backups = GradeBackups(directory: dir.appendingPathComponent("Backups"))
        let settings = RegistroSettingsStore(defaults: defaults)
        let store = GradesStore(fileStore: GradeFileStore(url: dir.appendingPathComponent("grades.json")),
                                backups: backups, registroSettings: settings)
        return RegistroSyncCoordinator(grades: store, backups: backups, settings: settings,
                                       keychain: KeychainStore(service: "com.davide.fmtII.registro.schedulingtests"),
                                       providers: [], defaults: defaults)
    }

    func testNoScheduleWhenDisconnected() {
        XCTAssertNil(RegistroBackgroundRefresh.schedule(registro: makeCoordinator()))
    }

    func testScheduleEarliestTwoHours() {
        defaults.set(RegistroProviderID.classeviva.rawValue, forKey: RegistroSyncCoordinator.Keys.provider)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let request = RegistroBackgroundRefresh.schedule(now: now, registro: makeCoordinator())
        XCTAssertEqual(request?.identifier, RegistroBackgroundRefresh.identifier)
        XCTAssertEqual(request?.earliestBeginDate, now.addingTimeInterval(2 * 3600))
    }

    // MARK: Notifiche

    private func fixture() -> (plan: SyncPlan, grades: [Grade]) {
        let g = Grade(subject: "Matematica", value: 7)
        var plan = SyncPlan()
        plan.newGradeIDs = [g.id]
        return (plan, [g])
    }

    func testNoNotificationOnFirstImport() {
        let f = fixture()
        for trigger in [SyncTrigger.background, .appOpen] {
            XCTAssertTrue(RegistroNotificationPolicy.gradesToNotify(
                plan: f.plan, trigger: trigger, isFirstImport: true, toggleOn: true, grades: f.grades).isEmpty)
        }
    }

    func testNotificationOnlyWhenToggleOn() {
        let f = fixture()
        XCTAssertTrue(RegistroNotificationPolicy.gradesToNotify(
            plan: f.plan, trigger: .background, isFirstImport: false, toggleOn: false, grades: f.grades).isEmpty)
        XCTAssertEqual(RegistroNotificationPolicy.gradesToNotify(
            plan: f.plan, trigger: .background, isFirstImport: false, toggleOn: true, grades: f.grades).map(\.id),
                       f.grades.map(\.id))
        XCTAssertEqual(RegistroNotificationPolicy.gradesToNotify(
            plan: f.plan, trigger: .appOpen, isFirstImport: false, toggleOn: true, grades: f.grades).count, 1)
        // Mai per la sync manuale, e solo per i voti davvero presenti.
        XCTAssertTrue(RegistroNotificationPolicy.gradesToNotify(
            plan: f.plan, trigger: .manual, isFirstImport: false, toggleOn: true, grades: f.grades).isEmpty)
        XCTAssertTrue(RegistroNotificationPolicy.gradesToNotify(
            plan: f.plan, trigger: .background, isFirstImport: false, toggleOn: true, grades: []).isEmpty)
    }

    func testInfoPlistDeclaresIdentifier() {
        let info = Bundle.main.infoDictionary
        XCTAssertEqual(info?["BGTaskSchedulerPermittedIdentifiers"] as? [String], [RegistroBackgroundRefresh.identifier])
        let modes = info?["UIBackgroundModes"] as? [String] ?? []
        XCTAssertTrue(modes.contains("fetch"))
        XCTAssertTrue(modes.contains("remote-notification"))
    }
}
