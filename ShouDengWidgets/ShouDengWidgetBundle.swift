import WidgetKit
import SwiftUI

@main
struct ShouDengWidgetBundle: WidgetBundle {
    var body: some Widget {
        ProtectedStatusWidget()
        GuardianStatusWidget()
        ProtectedTimerWidget()
        GuardianLiveActivity()
    }
}
