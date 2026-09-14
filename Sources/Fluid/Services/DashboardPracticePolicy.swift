/// Capture this at stop; later navigation must not turn unrelated dictation into practice.
nonisolated enum DashboardPracticePolicy {
    static func isPractice(dashboardVisible: Bool, normalDictation: Bool, targetPID: Int32?, appPID: Int32) -> Bool {
        dashboardVisible && normalDictation && targetPID == appPID
    }
}
