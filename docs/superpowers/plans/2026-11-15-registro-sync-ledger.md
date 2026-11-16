# SDD ledger — plan: docs/superpowers/plans/2026-11-15-registro-sync.md
Spec: docs/superpowers/specs/2026-11-15-registro-sync-design.md
Branch: feature/registro-sync (worktree /Users/davidesogos/Documents/FMT-II-v2.2), start 265d43c
Global constraints copy: .superpowers/sdd/2026-11-15-registro-sync/global-constraints.md

## Pre-flight
| Tasks | Shared | Finding |
|---|---|---|
| T1↔T2 | GradesStore.init(backups:) | T1 brief names `backups: GradeBackups?` but GradeBackups is created in T2 → T1 would not compile |
| T2↔T3 | manual backup rule vs Grade.origin | T2 runs before origin exists; T3 updates rule — consistent |
| T3↔T8 | RegistroOrigin.applied/editedFields, manualSnapshot | consistent |
| T5↔T8/T11/T12 | VotoRemoto, RemoteFetch, RegistroProvider | consistent |
| T6↔T8/T9 | SubjectMappingTable, RegistroSettingsStore.ignored | consistent |
| T8↔T9 | SyncPlan, ConflictDecision, PendingConflict | consistent |
| T9↔T13/T15 | RegistroSyncCoordinator API, NotificationManager | consistent |
| T10↔T11/T12 | docs/registri + fixtures; gate stops provider if unverifiable | consistent |
| Each task self-consistency | tests vs code vs files | T3 `testDeterministicIDIsStable` pins value after first green run (regression pin, acceptable); others consistent |
Ruling: T1 adds only `storageURL:` to GradesStore.init; `backups:` parameter is added in T2 — GradeBackups doesn't exist yet in T1 — cost if wrong: one signature change.
Ruling: tests that touch GradesStore use temp storageURL; existing StoreSyncTests keep default init — avoid touching real data — cost: none.

## Tasks
Task 1: implementer DONE_WITH_CONCERNS 4218404; review: Needs fixes (2 Important: unreadable-by-OS file overwritten later (pre-first-unlock CloudKit launch); failed quarantine write lets save overwrite)
Task 1: minor (deferred): GradesStore.save swallows write errors silently (pre-existing)
Task 1: minor (deferred): skippedOnLoad/quarantinedURL extras not @Published
Task 1: minor (deferred): testSaveIsAtomic name overclaims
Task 1: minor (deferred): StoreSyncTests uses real default URL
Task 1: fix round 1/5 (2 addressed, 0 open; commits 4218404..77ec78b)
Task 1: minor (deferred): while blocked each save re-runs load (repeat quarantine attempts)
Task 1: minor (deferred): deletions made while write-blocked are lost on merge (accepted by design note)
Task 1: complete (commits 265d43c..77ec78b, review clean)
Task 2: implementer DONE_WITH_CONCERNS a26cf0a (no separate RED run captured; existing tests write manual backup to real sim dir)
Task 2: review: Needs fixes (2 Important: restore ignores failed .preRestore snapshot; restore while write-blocked)
Task 2: minor (deferred, FLAG FOR FINAL REVIEW — user priority): manual backup overwritten with [] / mirrors deleteAll; consider keeping previous non-empty copy
Task 2: minor (deferred): rotation by filename timestamp (clock back, -10 vs -9 ordering)
Task 2: minor (deferred): list() decodes every snapshot; undecodable snapshot never rotates
Task 2: minor (deferred): tests — restore-fail doesn't assert no preRestore; no main-save-throws test; manual filter test identity until Task 3
Task 2: minor (deferred): existing tests write to real sim Application Support/GradeBackups
Task 2: fix round 1/5 (2 addressed, 0 open; commits a26cf0a..a5b0a0f)
Task 2: complete (commits 77ec78b..a5b0a0f, review clean)
Task 3: implementer DONE 924ae65 (fixture synthetic in 2.2 format)
Task 3: review: Approved
Task 3: minor (deferred): nested enums in origin (provider/kind/status/GradeType) decoded strictly — future cases would drop grades; consider tolerant decoding / frozen-wire note
Task 3: minor (deferred): fixture grades-v2.2.json synthetic; only first record asserted field by field; no legacy record missing weight/countsForAverage/modifiedAt
Task 3: minor (deferred, CARRY → Task 8): GradeEntrySheet.save trims subject/teacher → engine must trim remote strings before writing applied values, or editor save flags fields as edited
Task 3: minor (deferred, CARRY → Task 14): long rawValue strings ("discreto") in fixed-width grade badges
Task 3: minor (deferred): UUID test doesn't assert variant nibble
Task 3: complete (commits a5b0a0f..924ae65, review clean)
Task 4: implementer DONE b017de6 (concerns: 10+ → nil, giudizi not rescaled, a/b only adjacent, out-of-range providedNumeric → nil)
Task 4: review: Approved
Task 4: minor (deferred): "9/10" read as pair 9.5 (undocumented); typographic dashes (– −) → nil; "10+" → nil drops from average; giudizi not rescaled for maxGrade≠10
Task 4: minor (deferred, CARRY → Tasks 11/12): providedNumeric == 0 used as placeholder by a register would count as real 0 — adapters must pass nil for non-graded entries
Task 4: complete (commits 924ae65..b017de6, review clean)
Task 5: implementer DONE 49b5fbf
Task 5: review: Approved
Task 5: minor (deferred): Keychain update path doesn't re-assert kSecAttrAccessible; update-then-add not atomic
Task 5: minor (deferred): fingerprint try? ?? Data() would collapse hashes on encode failure; no golden hash test
Task 5: minor (deferred, CARRY → Tasks 11/12): URLSessionTransport lets URLError propagate unmapped — providers must map to .network
Task 5: minor (deferred): dead var in test; stub test doesn't assert logout/loginFields
Task 5: complete (commits b017de6..49b5fbf, review clean)
Task 6: implementer DONE e161952 (also updated SettingsSyncTests expected keys)
Task 6: review: Approved
Task 6: minor (deferred): JSON encode without sortedKeys/sorted set → redundant KVS pushes
Task 6: minor (deferred, FLAG FOR FINAL REVIEW): KVS whole-value replace — concurrent ignores on two devices can drop one → deleted imported grade reappears
Task 6: minor (deferred, CARRY → Task 8/9): RemoteSubjectRef.key uses bare id without provider prefix (single account at a time mitigates)
Task 6: minor (deferred, CARRY → Task 13): two remote subjects in one alias group proposed for same app subject — confirmation UI must show it; & not read as "e"; acronyms readableName
Task 6: complete (commits 49b5fbf..e161952, review clean)
Task 7: implementer DONE 2a4ca7c
Task 7: review: Approved
Task 7: minor (deferred): tie-order test doesn't exercise a tie; no test for runner-up threshold in isCertain (weak second certain; second == 0.5 blocks)
Task 7: complete (commits e161952..2a4ca7c, review clean)
Ruling: Task 8 — on certain link the registro becomes source of truth for provided fields (date, teacher if present, type if known, weight only via VotoRemoto.weight, countsForAverage, value = remote numeric within tolerance); note untouched; manualSnapshot taken before changes — spec §5 "Match certo" — cost: re-run link tests
Ruling: Task 8 — engine trims remote strings (subject name, teacher, rawValue) before writing Grade fields and applied values, so GradeEntrySheet's trim on save doesn't flag them as user edits — carries Task 3 minor — cost: none
Task 8: implementer DONE db910a8 (decisions: contested manual → strongest certain links, other import/conflict; linkTo with value diff > 0.01 → conflict; CARRY → Task 9 validator compares value with 0.01 tolerance)
Task 8: review: Approved
Ruling: Task 8 minor #1 (removal check ignores fetch.skippedCount) is load-bearing for "no false 'rimosso'" — CARRY → Task 9: coordinator passes coveredRange = nil to the engine when skippedCount > 0 and surfaces "voti non letti" — cost: one coordinator test
Ruling: contested manual grade → strongest certain match links (brief wins over spec "non conteso" reading) — values equal so no data change — cost: re-run engine tests if user prefers conflicts
Task 8: minor (deferred, FLAG FOR FINAL REVIEW): remoteInRange counts raw entries (duplicates/cancelled/pending inflate it)
Task 8: minor (deferred, FLAG FOR FINAL REVIEW): linkableManual doesn't check subject (stale linkTo) / non-numeric linkTo sets countsForAverage false
Task 8: minor (deferred, FLAG FOR FINAL REVIEW): link overwrites manual .giustifica type
Task 8: minor (deferred): untrimmed manual strings kept on link → later marked edited
Task 8: minor (deferred): test gaps (edited+removed+reactivated; idempotence after reactivation; cancelled remote on linked manual)
Ruling: Task 9 applyRegistroPlan stamps modifiedAt = now on every inserted/updated/linked grade (engine placeholder ignored) — iCloud LWW must see these as fresh; resurrection of deleted grades is handled by the ignored list — cost: none
Task 8: complete (commits 2a4ca7c..db910a8, review clean)
Task 9: implementer DONE e124fe4 (concerns: unlink keepImported turns non-numeric imported into "0" not counting; dedupe-dropped linked manual only in preSync snapshot not voti-manuali.json; added registroNeedsLogin key; connect throws leaving status; background not throttled)
Task 9: review: Needs fixes (1 Important: stale `prefetched` reused by confirmMapping → false 'rimosso' marks)
Task 9: minor (deferred, FLAG FOR FINAL REVIEW): unlink keepImported turns non-numeric imported into value 0 (rawValue lost except preUnlink snapshot)
Task 9: minor (deferred): dedupe-dropped linked manual's manualSnapshot not in voti-manuali.json
Task 9: minor (deferred, FLAG FOR FINAL REVIEW): confirmPendingPlan doesn't guard status / pending not cleared on failed sync
Task 9: minor (deferred, FLAG FOR FINAL REVIEW): connect / failing unlink overwrite status while .syncing (reentrancy guard weakened)
Task 9: minor (deferred, CARRY → Task 13): resolve() → syncNow(.manual) retries rejected credentials while needsLogin
Task 9: minor (deferred): confirmPendingPlan lacks isWritable() call; ignoreRegistroGrades writes ignored even if save fails; test gaps (dedupe blocked/snapshot fail, pending replaced, connect while syncing)
Task 9: fix round 1/5 (1 addressed, 0 open; commits e124fe4..cab129d)
Task 9: complete (commits db910a8..cab129d, review clean)
Task 10: implementer DONE_WITH_CONCERNS c87016b — gate: ClasseViva ready (weight scale TODO-CV7 → weight nil); Argo ready (weight TODO-AR11 → nil; argo-client-version header TODO-AR5); both impersonate official app (TODO-R1..R3); Argo "+/-" differs → always pass register numeric; Argo valore 0 placeholder for non-numeric
Ruling: weight unknown for both → providers emit VotoRemoto.weight = nil (app weight stays 1.0) per spec §1 "Peso" — user decides later — cost: averages ignore register weights until decided
Ruling: argo-client-version = documented constant in ArgoProvider, updated with FMT releases; server rejection maps to a clear error status, no retries — cost: Argo stops working until an app update if Argo enforces versions
Task 10: review: Needs fixes (3 Important: Argo "D" entries counted in skippedCount disables removal check; renewal/retry rules not expressible on RegistroProvider protocol; Argo codTipo != "V" (notes) would be imported as grades)
Ruling: weight gate (TODO-CV7/AR11) does not stop Tasks 11–12 — spec §1 "Peso" already prescribes weight nil + ask user after research; question goes to the user in the final report — cost: none until decided
Task 10: minor (deferred, CARRY → Task 11): ClasseViva 422 on data endpoint mapped to empty success (misread single source) — throw instead; 403 at login unmapped
Task 10: minor (deferred, CARRY → Tasks 11/12): fixtures lack a grade without teacherName/noAverage; illustrative +/- values in fixtures; Argo session fields → RegistroSession mapping unspecified; coveredRange end inclusivity
Task 10: minor (deferred): two wrong citation paths (AR-F Voto.kt, CV-D TIPI in nuvola_adatta.py)
Task 10: fix round 1/5 (3 addressed, 0 open; commits c87016b..fa7787a)
Task 10: complete (commits cab129d..fa7787a, review clean)
Ruling: Task 11 — a 422 on the ClasseViva grades endpoint throws .unexpectedFormat("422") instead of returning an empty success (single misread source; "ogni errore = nessuna scrittura") — cost: a user with no grades yet sees an error until TODO-CV12 is resolved
Task 11: implementer DONE_WITH_CONCERNS bf260e1 (decimalValue null → normalizer falls back to giudizi table; coveredRange end = midnight after last dateEnd; expiresAt +1h fallback; choices accounts rejected; MockTransport moved to shared file)
Task 11: review: Approved
Task 11: minor (deferred): no test where decimalValue disagrees with normalizer (regression guard); coveredRange end one day wide; date test near-tautological; unused struct Boom; absent componentDesc → nil kind uncommented; +1h expiresAt fallback untested
Task 11: complete (commits fa7787a..bf260e1, review clean)
Task 12: implementer DONE_WITH_CONCERNS cdfc8b7 (doc §3.4/§10 still says .notSupported for outdated version; client-version 1.30.2; 2-min expiry margin; multi-profile rejected; redirects only *.portaleargo.it max 10 GET; OAuth state not checked; device time if no Date header)
Task 12: review: Needs fixes (1 Important: step-2 non-2xx response without Location not mapped to invalidCredentials → repeated logins with bad password)
Task 12: minor (deferred, FLAG FOR FINAL REVIEW): transport errors in hop all → .network incl .notSupported (retried forever)
Task 12: minor (deferred): OAuth state not compared; redirect loop off-by-one; TimeZone.current snapshot; DateFormatter per call; only &amp; decoded; device-clock fallback undocumented
Task 12: minor (deferred, FLAG FOR FINAL REVIEW): Argo.md:295/:498 still say .notSupported for outdated client version (doc sync)
Task 12: QUESTION FOR USER: multiple Argo profiles (parent with several children) rejected with generic error (TODO-AR1); placeholder valore 0 + giudizio text → normalizer table (consistent with ClasseViva and spec §4)
Task 12: fix round 1/5 (1 addressed, 0 open; commits cdfc8b7..ef394ee)
Task 12: complete (commits bf260e1..ef394ee, review clean)
Task 13: implementer DONE 8e009a8..4c70c37 (concerns: disclaimer mentions iCloud propagation; mapping view shows key for confirmed subject with no grades; skipped count not persisted; notify toggle only saves pref)
Task 13: review: Approved
Task 13: minor (deferred, FLAG FOR FINAL REVIEW): wrong plural "1 giudizi"/"1 assessments" in unlink sheet
Task 13: minor (deferred, FLAG FOR FINAL REVIEW): syncNow(.manual) doesn't check credentialsRejected; "Sincronizza ora" re-enabled after other status changes
Task 13: minor (deferred): success haptic/dismiss even when sync fails; "Decidi dopo" alone triggers sync; identical conflict candidates indistinguishable (no time); delete-imported one tap; weak UI assertion; RegistroSettingsView 431 lines; mapping names/pending not persisted
Task 13: QUESTION FOR USER: disclaimer says imported grades reach user's own devices via iCloud (nuance vs "solo sul dispositivo")
Task 13: complete (commits ef394ee..4c70c37, review clean)
Task 14: implementer DONE_WITH_CONCERNS c5973f3 (iPad screenshots missing: UI test crashes in UIKit keyboard on iPad sims; DEBUG fake provider extended with -FMTFakeRegistroRemoval; Elimina has no confirmation dialog, contrary to brief)
Task 14: review: Needs fixes (2 Important: Elimina without confirmation; sheet "Tieni" saves stale grade, discards unsaved edits / overwrites newer sync; spec gap: no iPad screenshots)
Task 14: minor (deferred): time uses device locale not appFormatted; weak time test (NotNil only); Keep/Delete closures duplicated in GradesView; VoiceOver says "Dal registro" twice; UI test leaves debug screenshot writes + sleeps + fake fetch counter not reset; non-numeric register grade hidden from chart even after user sets a number
Task 14: fix round 1 implementer DONE_WITH_CONCERNS 032873a (iPad screenshot still failing: Lost connection at login step even with hardware keyboard; delete dialog is popover without visible Annulla on iPhone; no separate RED for sheet-keep test)
Task 14: fix round 1/5 (2 addressed, 1 open — iPad screenshot (login crash on iPad sim; DEBUG launch-arg path untried); commits c5973f3..032873a)
Task 14: minor (deferred): sheet "Tieni"/save form fields captured at open overwrite sync changes to same fields (same as save()); fallback to opened copy if sync deleted grade meanwhile — check store.update on missing id
Task 14: fix round 2/5 (1 addressed, 0 open; commits 032873a..a890692)
Task 14: minor (deferred): DEBUG autoConnect hook lacks run-once guard; UI test sleep(1) + unasserted screenshot write
Task 14: complete (commits 4c70c37..a890692, review clean)
Task 15: dispatched (BASE a890692, sonnet). Rulings in dispatch: notify only on .background/.appOpen (never .manual), not first import, toggle on, newGradeIDs non-empty; schedule() also after connect and on background, cancel on unlink
Task 15: implementer DONE_WITH_CONCERNS c6d9483 (BG handler/expiration not unit-tested; gradesToNotify takes [Grade]; first sync via confirmMapping/confirmPendingPlan never notifies; en placeholder changed to %@: %@)
Task 15: review: Approved
Task 15: minor (deferred, FLAG FOR FINAL REVIEW): .active appOpen sync not skipped under XCTest host (other managers check XCTestConfigurationFilePath) — test runs could sync/write with a real linked account in simulator defaults
Task 15: minor (deferred, FLAG FOR FINAL REVIEW): BG launchHandler isolation via nonisolated(unsafe); expirationHandler attached after MainActor hop — use `using: .main` + MainActor.assumeIsolated
Task 15: minor (deferred): coordinator calls AppStores.shared/NotificationManager.shared globals (notify wiring not unit-testable); expiration relies on cancellation propagation + leaves status .error; no test for empty newGradeIDs or nil→no submit; test defaults suite not removed; schedule still submits while needsLogin
Task 15: complete (commits a890692..c6d9483, review clean)
Task 16: dispatched (BASE c6d9483, sonnet). Ruling: archive only, no upload; 'what's new' banner for 2.3 not in plan scope — ask user in final report
Task 16: implementer DONE_WITH_CONCERNS 0a24b3e (archive OK 2.3.0(1) not uploaded; RotationPagerUITests skipped on iPhone — not run on iPad; full suite not re-run after removing 2 stale catalog entries; PrivacyInfo unchanged; RELEASE-NOTES TODOs for user)
Task 16: review: Needs fixes (2 Important: RotationPagerUITests never run on iPad after Voti layout change; RELEASE-NOTES 5.2.2 note says "same access as providers' apps", understating official-app identifier use (README TODO-R1))
Task 16: minor (deferred): RELEASE-NOTES points to transient task report (:54, :82); TODO lines inside paste-ready review block; privacy-policy.md update only TODO; full unit suite not re-run after stale-key removal
Task 16: fix round 1 implementer DONE a731a0c (iPad RotationPager 4/4 + autoConnect 1/1 pass; 5.2.2 sentence → TODO; unit 296/0/4)
Task 16: fix round 1/5 (2 addressed, 0 open; commits 0a24b3e..a731a0c)
Task 16: minor (deferred): Italian internal 5.2.2 note generic, lacks TODO-R1 identifiers placeholder
Task 16: complete (commits c6d9483..a731a0c, review clean)
Final review: dispatched (merge base 42093a4 = origin/main, head a731a0c)
Final review: With fixes (0 Critical, 3 Important: rateLimited/403 doesn't stop automatic retries (contradicts UI text + spec §7); "Tieni" undone by next sync (markRemoved re-marks); dedupe in applyRemote can drop a distinct linked manual grade (T9 deferred minor regraded up))
Final: fix wave includes also flagged cheap fixes: plural "1 giudizi"; Argo.md .notSupported doc drift; syncNow(.manual) credentialsRejected guard
Final: minor (deferred): needsLogin footer text wrong when credentials merely missing; stale Keychain items after reinstall (UserDefaults wiped); pendingPlan no age limit; edit sheet saves from open-time copy; unlink-keep non-numeric → "0"; link can overwrite giustifica type; HTTPTransport auto-redirects carry custom headers off-host; BG schedule uses AppStores.shared not self; origin decoded strictly (future enum cases drop grades in 2.3)
Final: fix wave DONE_WITH_CONCERNS 8e8fc00 (303/0/4 unit, UI 7/7; dedupe winner among linked manuals = lowest id (deterministic) and losers restored as manual — deviates from spec §2 'remove loser'; .keptAfterRemoval added; auto-sync blocked after 403/429/notSupported/clientVersion until manual action)
Final: fix wave re-review: all 6 addressed, no new Critical/Important (commits a731a0c..8e8fc00)
Final: minor (deferred): dedupe restore stamps modifiedAt=now, can beat a concurrent edit on another device; sheet "Tieni" can mark an already-active grade kept (set kept only if removed); restored manual may sit beside a pure import of a second register grade (visible duplicate); SyncMerge cached payload could re-add nil origin (not reachable today, fix before next schema change)
Final: Ruling: dedupe among multiple linked manual grades picks lowest id as winner and restores losers as plain manual grades (spec §2 said remove loser) — protects user data + deterministic convergence — cost if wrong: occasional visible duplicate the user deletes by hand
