import SwiftUI
import UsageCore

struct AccountCardView: View {
    let account: DisplayAccount
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var profile: Profile { account.usage.profile }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(profile.email ?? profile.id)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if profile.email != nil {
                Text(profile.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if account.usage.plan != "—" {
                Text(account.usage.plan.uppercased())
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = account.snapshot {
            ForEach(snapshot.limits) { LimitRowView(limit: $0, now: now) }
            if account.isStale {
                Label("Stale — \(staleReason) · from \(UsageFormat.resetClock(snapshot.fetchedAt, now: now))",
                      systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } else {
            switch account.usage.status {
            case .noLogin:
                Text("No Claude subscription login")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .authExpired(let message):
                Label(message, systemImage: "key.slash")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            case .rateLimited, .failed:
                Label(staleReason, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            case .ok:
                EmptyView()
            }
        }
    }

    private var staleReason: String {
        switch account.usage.status {
        case .rateLimited: "rate limited"
        case .failed(let message): message
        default: ""
        }
    }
}
