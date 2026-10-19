import SwiftUI
import StrandDesign

/// The "looks like a workout" suggestion on a sheet of its own, raised by a tap on its notification. It sits above
/// whatever screen the app was on, so there is always something on screen to answer: the suggestion, or why there
/// is none.
struct WorkoutSuggestionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var repo: Repository

    var body: some View {
        NavigationStack {
            ScrollView {
                AutoWorkoutCard(alwaysShow: true)
                    .padding(NoopMetrics.space4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle(Text("Workout suggestion"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #endif
    }
}
