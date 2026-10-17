import SwiftUI

struct ReportListingButton: View {
    @Environment(SessionContext.self) private var session
    let listing: FoodListing
    @State private var showReport = false
    @State private var showConfirmation = false
    @State private var reportSubmitted = false

    var body: some View {
        if !session.matches(listing.postedByDeviceID) {
            Button { reportSubmitted = false; showReport = true } label: {
                Label("Report listing", systemImage: "flag")
            }
            .sheet(isPresented: $showReport, onDismiss: {
                if reportSubmitted { showConfirmation = true }
            }) {
                ReportListingSheet(listing: listing) {
                    reportSubmitted = true
                    showReport = false
                }
            }
            .alert("Report received", isPresented: $showConfirmation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your report has been sent for review. Thank you for helping keep SharePlate safe.")
            }
        }
    }
}
