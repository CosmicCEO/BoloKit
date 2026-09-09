//
//  MessagesView.swift
//  Bolo 2026
//
//  1.1 backlog C.4 -- the port's equivalent of `GSXBoloController.m`'s `messagesTextView` +
//  `messageTextField`/`messageTarget` radio matrix (`GSXBoloController.m:1393-1419,2707-2729`),
//  driven by `GameSession.messages`/`sendMessage(text:target:)` (`GameSession.swift`'s own C.4
//  header). Same visual/structural shape as `PlayerStatusView` -- a `NavigationStack` sheet with
//  a `List`, a "Done" toolbar action, and `TimelineView`-driven polling rather than SwiftUI
//  observation, for the identical reason `PlayerStatusView`'s own header states: `GameSession`
//  isn't `ObservableObject` by design (`state` is deliberately not a single source of truth on
//  every path).
//
//  Only `.everyone`/`.allies`/`.nearby` are offered -- matches `MessageTarget`'s own case set,
//  which already excludes `MSGGAME` (server-only synthetic target, never a player-chosen one;
//  see `ChatMessage.swift`'s header).

import BoloKit
import BoloNet
import SwiftUI

struct MessagesView: View {
    let session: GameSession
    let onDone: () -> Void

    @State private var draft: String = ""
    @State private var target: MessageTarget = .everyone

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            content(snapshot: session.state, messages: session.messages)
        }
    }

    private func content(snapshot: GameState, messages: [ChatMessage]) -> some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    List(messages) { message in
                        messageRow(message, snapshot: snapshot).id(message.id)
                    }
                    .onChange(of: messages.last?.id) { _, newValue in
                        guard let newValue else { return }
                        withAnimation { proxy.scrollTo(newValue, anchor: .bottom) }
                    }
                }

                Divider()

                HStack {
                    Picker("To", selection: $target) {
                        ForEach(MessageTarget.allCases, id: \.self) { target in
                            Text(target.label).tag(target)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)

                    TextField("Message", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(send)

                    Button("Send", action: send)
                        .disabled(draft.isEmpty)
                }
                .padding(8)
            }
            .navigationTitle("Messages")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 360)
    }

    private func send() {
        guard !draft.isEmpty else { return }
        session.sendMessage(text: draft, target: target)
        draft = ""
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessage, snapshot: GameState) -> some View {
        HStack(alignment: .top) {
            Text(message.senderName.isEmpty ? "Player \(message.player)" : message.senderName)
                .fontWeight(.semibold)
                .foregroundStyle(message.player == snapshot.localPlayer ? Color.accentColor : .primary)
            Text(message.text)
            Spacer()
        }
        .font(.callout)
    }
}
