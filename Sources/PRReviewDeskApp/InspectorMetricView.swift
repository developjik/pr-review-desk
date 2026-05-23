import SwiftUI

struct InspectorMetric: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tone: AppStatusTone
}

struct InspectorMetricGroup: View {
    let metrics: [InspectorMetric]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(metrics) { metric in
                    InspectorMetricCell(metric: metric, fillsWidth: false)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(metrics) { metric in
                    InspectorMetricCell(metric: metric, fillsWidth: true)
                }
            }
        }
    }
}

private struct InspectorMetricCell: View {
    let metric: InspectorMetric
    let fillsWidth: Bool

    var body: some View {
        Label(metric.title, systemImage: metric.systemImage)
            .font(.caption)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(AppTheme.foreground(metric.tone))
            .background(AppTheme.background(metric.tone), in: RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
            .fixedSize(horizontal: !fillsWidth, vertical: false)
            .accessibilityLabel(metric.title)
    }
}
