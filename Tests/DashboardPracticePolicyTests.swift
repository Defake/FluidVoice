@main
struct DashboardPracticePolicyTests {
    static func main() {
        precondition(DashboardPracticePolicy.isPractice(dashboardVisible: true, normalDictation: true, targetPID: 100, appPID: 100))
        for target: Int32? in [nil, 200] {
            precondition(!DashboardPracticePolicy.isPractice(dashboardVisible: true, normalDictation: true, targetPID: target, appPID: 100))
        }
        precondition(!DashboardPracticePolicy.isPractice(dashboardVisible: false, normalDictation: true, targetPID: 100, appPID: 100))
        precondition(!DashboardPracticePolicy.isPractice(dashboardVisible: true, normalDictation: false, targetPID: 100, appPID: 100))
        print("PASS: Dashboard practice excludes external, missing-target, other-page, and non-dictation sessions")
    }
}
