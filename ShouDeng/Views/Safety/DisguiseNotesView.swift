import SwiftUI

// MARK: - Disguise Notes View
//
// A functional notes app shell that hides the real safety app.
// Type the secret phrase (default "help me") to reveal the real app.

struct DisguiseNotesView: View {
    @ObservedObject private var disguiseService = DisguiseModeService.shared

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

        static var samples: [NoteItem] {
            [
                NoteItem(title: "Shopping List", body: "Milk, eggs, bread, butter, apples, orange juice", date: Date().addingTimeInterval(-3600)),
                NoteItem(title: "Meeting Notes", body: "Discuss Q4 budget\nReview team assignments\nSet deadlines for next sprint", date: Date().addingTimeInterval(-86400)),
                NoteItem(title: "Ideas", body: "Look into weekend hiking trails\nTry new pasta recipe\nCall dentist for appointment", date: Date().addingTimeInterval(-172800)),
                NoteItem(title: "Reminders", body: "Pay electricity bill\nRenew gym membership\nSchedule car service", date: Date().addingTimeInterval(-259200)),
            ]
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
        .navigationTitle("Notes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let newNote = NoteItem(title: "New Note", body: "", date: Date())
                    notes.insert(newNote, at: 0)
                    selectedNote = newNote
                    editingTitle = newNote.title
                    editingText = ""
                    isEditing = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
    }

    // MARK: - Note Editor (with secret phrase detection)

    private func noteEditorView(_ note: NoteItem) -> some View {
        VStack(spacing: 0) {
            TextField("Title", text: $editingTitle)
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
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Notes")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // Share (does nothing, just looks real)
                } label: {
                    Image(systemName: "square.and.arrow.up")
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
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "h:mm a"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            formatter.dateFormat = "M/d/yy"
        }
        return formatter.string(from: date)
    }
}
