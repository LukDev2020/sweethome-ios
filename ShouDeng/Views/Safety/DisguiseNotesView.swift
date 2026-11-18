import SwiftUI

// MARK: - Disguise Notes View
//
// A functional notes app shell that hides the real safety app.
// Type the secret phrase (default "help me") to reveal the real app.

struct DisguiseNotesView: View {
    @ObservedObject private var disguiseService = DisguiseModeService.shared
    @ObservedObject private var lang = LanguageManager.shared

    @State private var notes: [NoteItem] = NoteItem.samples
    @State private var selectedNote: NoteItem?
    @State private var editingText = ""
    @State private var editingTitle = ""
    @State private var isEditing = false

    struct NoteItem: Identifiable {
        let id = UUID()
        var title: String
        var body: String
        var date: Date

        /// Everyday notes in the person's language, so the shell looks like their own notes app
        static var samples: [NoteItem] {
            let lang = LanguageManager.shared
            return [
                ("shopping", -3600.0), ("meeting", -86400.0), ("ideas", -172800.0), ("reminders", -259200.0),
            ].map { name, age in
                NoteItem(title: lang.localized("disguise.notes.sample.\(name).title"),
                         body: lang.localized("disguise.notes.sample.\(name).body"),
                         date: Date().addingTimeInterval(age))
            }
        }
    }

    var body: some View {
        NavigationStack {
            if isEditing, let note = selectedNote {
                noteEditorView(note)
            } else {
                noteListView
            }
        }
    }

    // MARK: - Note List

    private var noteListView: some View {
        List {
            ForEach(notes) { note in
                Button {
                    selectedNote = note
                    editingTitle = note.title
                    editingText = note.body
                    isEditing = true
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                        HStack(spacing: 8) {
                            Text(formatDate(note.date))
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            Text(note.body.prefix(40) + (note.body.count > 40 ? "..." : ""))
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .onDelete { indexSet in
                notes.remove(atOffsets: indexSet)
            }
        }
        .listStyle(.plain)
        .navigationTitle(lang.localized("disguise.notes"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let newNote = NoteItem(title: lang.localized("disguise.notes.newNote"), body: "", date: Date())
                    notes.insert(newNote, at: 0)
                    selectedNote = newNote
                    editingTitle = newNote.title
                    editingText = ""
                    isEditing = true
                } label: {
                    Label(lang.localized("disguise.notes.newNote"), systemImage: "square.and.pencil")
                }
            }
        }
    }

    // MARK: - Note Editor (with secret phrase detection)

    private func noteEditorView(_ note: NoteItem) -> some View {
        VStack(spacing: 0) {
            TextField(lang.localized("disguise.notes.titlePlaceholder"), text: $editingTitle)
                .font(.system(size: 22, weight: .bold))
                .padding(.horizontal, 16)
                .padding(.top, 16)

            TextEditor(text: $editingText)
                .font(.system(size: 16))
                .padding(.horizontal, 12)
                .onChange(of: editingText) { _, newValue in
                    checkSecretPhrase(newValue)
                }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    // Save and go back
                    if let index = notes.firstIndex(where: { $0.id == note.id }) {
                        notes[index].title = editingTitle
                        notes[index].body = editingText
                        notes[index].date = Date()
                    }
                    isEditing = false
                    selectedNote = nil
                } label: {
                    Label(lang.localized("disguise.notes"), systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                // Shares the note's text, like any notes app
                ShareLink(item: [editingTitle, editingText].filter { !$0.isEmpty }.joined(separator: "\n")) {
                    Label(lang.localized("disguise.notes.share"), systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    // MARK: - Secret Phrase Detection

    private func checkSecretPhrase(_ text: String) {
        let phrase = disguiseService.notesSecretPhrase.lowercased()
        guard !phrase.isEmpty else { return }
        if text.lowercased().hasSuffix(phrase) {
            disguiseService.handleSecretGestureDetected()
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: lang.current.rawValue)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            formatter.timeStyle = .short
        } else if calendar.isDateInYesterday(date) {
            // "Yesterday" / "昨天" / "昨日" / "Hier"
            formatter.dateStyle = .short
            formatter.doesRelativeDateFormatting = true
        } else {
            formatter.dateStyle = .short
        }
        return formatter.string(from: date)
    }
}
