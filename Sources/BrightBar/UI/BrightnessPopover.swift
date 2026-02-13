import SwiftUI

/// SwiftUI view for the menu bar popover.
/// Shows monitor picker (when multiple are available), brightness slider, and current percentage.
struct BrightnessPopover: View {
    @ObservedObject var brightnessManager: BrightnessManager

    var body: some View {
        VStack(spacing: 0) {
            // Monitor list (always shown when displays are available)
            if !brightnessManager.availableDisplays.isEmpty {
                monitorPicker
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 4)
            }

            // Brightness control for active display
            brightnessControl
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 10)

            Divider()

            // Footer
            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 280)
    }

    // MARK: - Monitor Picker

    private var monitorPicker: some View {
        VStack(spacing: 6) {
            ForEach(brightnessManager.availableDisplays) { display in
                monitorRow(display)
            }
        }
    }

    private func monitorRow(_ display: BrightnessManager.DisplayInfo) -> some View {
        let isActive = display.index == brightnessManager.activeDisplayIndex

        return Button {
            brightnessManager.selectDisplay(at: display.index)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "display")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isActive ? .accentColor : .secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(display.name)
                        .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                        .foregroundColor(isActive ? .primary : .secondary)
                        .lineLimit(1)

                    Text("\(display.resolution)  \(display.refreshRate)")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isActive {
                    Text(percentageText)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Brightness Control

    private var brightnessControl: some View {
        VStack(spacing: 8) {
            // Slider
            HStack(spacing: 10) {
                Image(systemName: "sun.min.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Slider(
                    value: Binding(
                        get: { brightnessManager.brightness },
                        set: { brightnessManager.setBrightness($0, showOSD: false) }
                    ),
                    in: 0...1
                )
                .controlSize(.small)
                .disabled(!brightnessManager.isDisplayConnected)

                Image(systemName: "sun.max.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundColor(.secondary)

            Spacer()

            if !brightnessManager.isDisplayConnected {
                Text("No DDC display")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            }
        }
    }

    // MARK: - Computed

    private var percentageText: String {
        "\(Int(round(brightnessManager.brightness * 100)))%"
    }

    private var displayIcon: String {
        brightnessManager.isDisplayConnected ? "display" : "display.trianglebadge.exclamationmark"
    }
}
