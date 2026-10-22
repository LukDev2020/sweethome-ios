import WidgetKit
import SwiftUI

@main
struct ShouDengWidgetBundle: WidgetBundle {
    var body: some Widget {
        ProtectedStatusWidget()
        GuardianStatusWidget()
        ProtectedTimerWidget()
        if #available(iOS 17.0, *) {
            SOSWidget()
        }
        ProtectedLiveActivity()
        GuardianLiveActivity()
    }
}
