import Foundation

// MARK: - Work log in the Obsidian vault

/// Writes what has left the lists into the Obsidian vault, one Markdown file
/// per year with a heading and a table for each month, so it can be read back
/// at review time.
///
/// One-way, and the files are generated: each one is rebuilt whole from
/// `swept.json` rather than appended to. The rows are a Markdown table, and a
/// table only stays a table if nothing is ever typed between its rows — an
/// append-only file that the user also writes in would break it the first time
/// they did. So the file belongs to the app, says so at the top, and the
/// review itself is written in a note of its own.
///
/// Nothing here is read back. If the vault is not there the export is simply
/// skipped; `swept.json` is the record and this is a view of it.
enum WorkLog {
    /// The vault this writes into. Its absence means "not set up on this Mac",
    /// so the folder under it is created but the vault never is.
    static let vault = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Notes", isDirectory: true)
    static let folder = vault.appendingPathComponent("04-干活记录", isDirectory: true)

    static func export(_ items: [Store.SweptItem]) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: vault.path, isDirectory: &isDir),
              isDir.boolValue else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let byYear = Dictionary(grouping: items) { year.string(from: $0.done) }
        for (key, rows) in byYear {
            let url = folder.appendingPathComponent("\(key).md")
            let text = render(year: key, rows)
            // Unchanged years are left alone, so a rebuild at launch does not
            // touch every file and hand the sync each of them to upload.
            if (try? String(contentsOf: url, encoding: .utf8)) == text { continue }
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func render(year key: String, _ rows: [Store.SweptItem]) -> String {
        let dropped = rows.filter { $0.outcome == .dropped }.count
        var lines = [
            "---",
            "类型: 干活记录",
            "年份: \(key)",
            "完成: \(rows.count - dropped)",
            "叉掉: \(dropped)",
            "---",
            "> 由 Eaves 自动生成，每有一条待办结束就会重写，手改会被覆盖。",
        ]
        // Newest month first, and newest row first within it: at review the
        // question is almost always about the last few weeks.
        let byMonth = Dictionary(grouping: rows) { cal.component(.month, from: $0.done) }
        for m in byMonth.keys.sorted(by: >) {
            let rows = byMonth[m]!.sorted { $0.done > $1.done }
            lines += ["", "## \(m) 月（\(tally(rows))）"]
            // One table per list within the month, the busiest first, so the
            // review reads as "how far did each line of work get". Ties go
            // by name so the order does not shuffle between rebuilds.
            let byNote = Dictionary(grouping: rows, by: \.note)
            let order = byNote.keys.sorted {
                (byNote[$0]!.count, $1) > (byNote[$1]!.count, $0)
            }
            for name in order {
                lines += [
                    "",
                    "### \(name.isEmpty ? "未命名" : name)（\(tally(byNote[name]!))）",
                    "",
                    "| 结束时间 | 状态 | 事项 | 用时 | 步骤 |",
                    "| --- | --- | --- | --- | --- |",
                ]
                for r in byNote[name]! {
                    let state = r.outcome == .dropped ? "✖ 叉掉" : "✅ 完成"
                    let took = r.created.map { duration(r.done.timeIntervalSince($0)) } ?? "—"
                    // Numbered in the order they sat under the item. A table cell
                    // cannot hold a real list, so the numbers are plain text.
                    let steps = (r.steps ?? []).enumerated()
                        .map { "\($0.offset + 1). " + cell($0.element) }
                        .joined(separator: "<br>")
                    lines.append("| \(stamp.string(from: r.done)) | \(state) | \(cell(r.text)) "
                                 + "| \(took) | \(steps) |")
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// "完成 3 · 叉掉 1", or just "完成 3" when nothing was dropped.
    private static func tally(_ rows: [Store.SweptItem]) -> String {
        let out = rows.filter { $0.outcome == .dropped }.count
        return out == 0 ? "完成 \(rows.count)" : "完成 \(rows.count - out) · 叉掉 \(out)"
    }

    /// Text as a table cell: a `|` would end the cell and a newline the row.
    private static func cell(_ s: String) -> String {
        s.replacingOccurrences(of: "|", with: "\\|")
         .replacingOccurrences(of: "\n", with: " ")
    }

    /// Coarse on purpose. At review the question is "an hour or a week", and
    /// "3 天 4 小时 12 分" only makes that harder to see down a column.
    private static func duration(_ t: TimeInterval) -> String {
        let t = max(t, 0)
        if t < 3600 { return "\(max(Int(t / 60), 1)) 分钟" }
        if t < 86400 { return "\(Int((t / 3600).rounded())) 小时" }
        return "\(Int((t / 86400).rounded())) 天"
    }

    private static let year: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy"
        return f
    }()

    /// The same calendar and zone the formatters use, so a row near midnight
    /// lands under the month its own timestamp shows.
    private static let cal = Calendar.current

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM-dd EEE HH:mm"
        return f
    }()
}
