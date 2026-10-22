import AppKit
import SwiftUI

// A tab because an LSUIElement app has no app menu to hold the standard About item.
struct AboutTab: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Project") {
                    Link(AppInfo.repositoryLabel, destination: AppInfo.repositoryURL)
                }
                LabeledContent("Report an issue") {
                    Link("GitHub Issues", destination: AppInfo.issuesURL)
                }
                LabeledContent("License") {
                    Link("MIT", destination: AppInfo.licenseURL)
                }
            } header: {
                header
            }
            Section {
                Label {
                    Text("""
                        Sugarglider only displays the data reported by your Nightscout site, which may \
                        be outdated or inaccurate. It is not a medical device and does not provide \
                        alarms. Never rely on it to detect high or low glucose levels or an \
                        interruption in insulin delivery. Do not use it to make treatment decisions.
                        """)
                } icon: {
                    Image(systemName: "info.circle")
                }
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var header: some View {
        VStack(spacing: 2) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
                .padding(.bottom, 4)
            Text("Sugarglider")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
            Text(AppInfo.versionText)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text(AppInfo.copyright)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 12)
    }
}

enum AppInfo {
    static let repositoryLabel = "nvmddev/sugarglider"
    static let repositoryURL = URL(string: "https://github.com/nvmddev/sugarglider")!
    static let issuesURL = repositoryURL.appending(path: "issues")
    static let licenseURL = repositoryURL.appending(path: "blob/main/LICENSE")

    static var versionText: String {
        versionText(short: bundleString("CFBundleShortVersionString"),
                    build: bundleString("CFBundleVersion"))
    }

    static func versionText(short: String?, build: String?) -> String {
        guard let short, !short.isEmpty else { return String(localized: "Development build") }
        guard let build, !build.isEmpty else { return String(localized: "Version \(short)") }
        return String(localized: "Version \(short) (\(build))")
    }

    static var copyright: String {
        bundleString("NSHumanReadableCopyright") ?? "© 2026 nevermind.dev"
    }

    private static func bundleString(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
