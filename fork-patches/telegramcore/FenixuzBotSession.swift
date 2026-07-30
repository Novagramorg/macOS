import Foundation
import Postbox
import SwiftSignalKit

// Bot-session behaviour (Novagram / Fenixuz fork). Port of the iOS fork's
// submodules/TelegramCore/Sources/FenixuzBotSession.swift.
//
// A bot session logs in fine (see FenixuzBotAuthorization.swift) but the server blocks the
// user-only sync RPCs for it, so several of Telegram's managed operations retry forever and
// leave the UI stuck. Everything here is gated on the session actually being a bot, so normal
// phone/QR accounts keep upstream behaviour untouched.
//
// All seven helpers are ported and all are hooked, matching the iOS fork one-for-one:
// hole handling (chat list + message history), DM read-state seeding, forced chat inclusion,
// folder .allChats injection, and the muted-peer commit.

private struct FenixuzBotSessionState: Codable {
    var isBot: Bool
}

// Length-8 key never collides with the upstream length-4 preference keys.
private let fenixuzBotSessionPreferencesKey: ValueBoxKey = {
    let key = ValueBoxKey(length: 8)
    key.setInt64(0, value: 0x46_65_6E_78_42_6F_74_31) // "FenxBot1"
    return key
}()

func setFenixuzBotSession(transaction: Transaction, isBot: Bool) {
    transaction.setPreferencesEntry(key: fenixuzBotSessionPreferencesKey, value: PreferencesEntry(FenixuzBotSessionState(isBot: isBot)))
}

func fenixuzIsBotSession(transaction: Transaction) -> Bool {
    return transaction.getPreferencesEntry(key: fenixuzBotSessionPreferencesKey)?.get(FenixuzBotSessionState.self)?.isBot ?? false
}

// Robust variant: true if the login flag is set OR the account's own peer is a bot. The peer check
// makes this work retroactively for accounts logged in before the flag existed (the account's own
// bot user arrives in the update `users` array and is stored with botInfo), so no re-login needed.
func fenixuzIsBotSession(transaction: Transaction, accountPeerId: PeerId) -> Bool {
    if fenixuzIsBotSession(transaction: transaction) {
        return true
    }
    return (transaction.getPeer(accountPeerId) as? TelegramUser)?.botInfo != nil
}

// Chat-list hole handling for a bot session. A bot can't call messages.getDialogs
// (BOT_METHOD_INVALID), so the normal fetchChatListHole retries forever and the chat list stays
// stuck on an unresolved hole — it renders a spinner and never shows the locally-received chats.
// For a bot we instead REMOVE the hole so the list counts as loaded. Normal accounts fetch as before.
func fenixuzManagedChatListHole(postbox: Postbox, network: Network, accountPeerId: PeerId, groupId: PeerGroupId, hole: ChatListHole) -> Signal<Never, NoError> {
    return postbox.transaction { transaction -> Bool in
        return fenixuzIsBotSession(transaction: transaction, accountPeerId: accountPeerId)
    }
    |> mapToSignal { isBot -> Signal<Never, NoError> in
        if isBot {
            return postbox.transaction { transaction in
                transaction.replaceChatListHole(groupId: groupId, index: hole.index, hole: nil)
                Logger.shared.log("FENIX", "removed chat-list hole for bot session (group \(groupId))")
            }
            |> ignoreValues
        } else {
            return fetchChatListHole(postbox: postbox, network: network, accountPeerId: accountPeerId, groupId: groupId, hole: hole)
        }
    }
}

// Message-history-hole handling for a bot session. Opening a chat fills history via
// messages.getHistory, which bots can't call; the fetch errors out so the hole is never removed
// and the chat view stays stuck on it, never rendering the messages that did arrive over the
// update stream. For a bot we REMOVE the hole so the chat opens. Normal accounts fetch.
func fenixuzManagedMessageHistoryHole(accountPeerId: PeerId, network: Network, postbox: Postbox, hole: MessageHistoryViewPeerHole, direction: MessageHistoryViewRelativeHoleDirection, space: MessageHistoryHoleOperationSpace, count: Int) -> Signal<Never, NoError> {
    return postbox.transaction { transaction -> Bool in
        return fenixuzIsBotSession(transaction: transaction, accountPeerId: accountPeerId)
    }
    |> mapToSignal { isBot -> Signal<Never, NoError> in
        if isBot {
            return postbox.transaction { transaction in
                transaction.removeHole(peerId: hole.peerId, threadId: hole.threadId, namespace: hole.namespace, space: space, range: 1 ... (Int32.max - 1))
                Logger.shared.log("FENIX", "removed message-history hole for bot session (peer \(hole.peerId))")
            }
            |> ignoreValues
        } else {
            return fetchMessageHistoryHole(accountPeerId: accountPeerId, source: .network(network), postbox: postbox, peerInput: .direct(peerId: hole.peerId, threadId: hole.threadId), namespace: hole.namespace, direction: direction, space: space, count: count)
            |> ignoreValues
        }
    }
}

// Bot sessions can't sync notification settings to the server: their peers usually have no
// accessHash, so apiInputPeer is nil and pushPeerNotificationSettings lands on a branch that
// DISCARDS the pending settings without committing them to CURRENT. Since getEffective falls back
// to current, the peer reverts to unmuted and its (locally-generated) notifications resurface — a
// mute never sticks. For a bot session, commit to CURRENT so it holds. No-op for normal accounts,
// whose peers resolve apiInputPeer and never reach the discard branch.
func fenixuzCommitPendingSettingsIfBot(transaction: Transaction, peerId: PeerId, settings: PeerNotificationSettings) {
    guard let accountPeerId = (transaction.getState() as? AuthorizedAccountState)?.peerId else {
        return
    }
    guard fenixuzIsBotSession(transaction: transaction, accountPeerId: accountPeerId), let settings = settings as? TelegramPeerNotificationSettings else {
        return
    }
    transaction.updateCurrentPeerNotificationSettings([peerId: settings])
}

// Folders (chat list filters) for a bot session. Bots never receive the server's .allChats default
// (getDialogFilters is blocked), so a created folder yields a single-tab state and the folder tab
// strip stays hidden (it needs >= 2 tabs). Prepend .allChats for a bot so the strip shows.
func fenixuzEnsureAllChatsForBotFilters(transaction: Transaction, filters: inout [ChatListFilter]) {
    guard !filters.isEmpty else {
        return
    }
    guard let accountPeerId = (transaction.getState() as? AuthorizedAccountState)?.peerId, fenixuzIsBotSession(transaction: transaction, accountPeerId: accountPeerId) else {
        return
    }
    if !filters.contains(.allChats) {
        filters.insert(.allChats, at: 0)
    }
}

// Seed a from-scratch cloud read state for an incoming DM in a bot session so the unread badge works.
// Bots can't call getPeerDialogs/getHistory (which normally seed a DM's read state), so a DM with no
// read state never counts as unread. Seed count:0 BEFORE addMessages; the message add's own
// addIncomingMessages then increments it through the normal path. Only for CloudUser peers with no
// existing cloud read state — never clobber a real one. Groups already work via channel pts.
func fenixuzInitializeBotDMReadState(isBotSession: Bool, transaction: Transaction, messages: [StoreMessage], location: AddMessagesLocation) {
    guard isBotSession, case .UpperHistoryBlock = location else {
        return
    }
    for message in messages {
        guard message.flags.contains(.Incoming), case let .Id(id) = message.id, id.peerId.namespace == Namespaces.Peer.CloudUser else {
            continue
        }
        let hasCloudState = transaction.getCombinedPeerReadState(id.peerId)?.states.contains(where: { $0.0 == Namespaces.Message.Cloud }) ?? false
        if !hasCloudState {
            transaction.resetIncomingReadStates([id.peerId: [Namespaces.Message.Cloud: .idBased(maxIncomingReadId: 0, maxOutgoingReadId: 0, maxKnownId: 0, count: 0, markedUnread: false)]])
        }
    }
}

// Force chat-list inclusion for every peer that received a message in a bot session, so the chat
// materializes from the message alone. Without this a brand-new peer's message lands in Postbox
// history but never produces a chat-list row, because inclusion normally comes from the dialogs
// sync a bot cannot run.
func fenixuzForceBotChatInclusion(isBotSession: Bool, transaction: Transaction, messages: [StoreMessage], location: AddMessagesLocation) {
    guard isBotSession, case .UpperHistoryBlock = location else {
        return
    }
    for message in messages {
        if case let .Id(id) = message.id {
            updatePeerChatInclusionWithMinTimestamp(transaction: transaction, id: id.peerId, minTimestamp: message.timestamp, forceRootGroupIfNotExists: true)
            Logger.shared.log("FENIX", "forced bot chat inclusion for peer \(id.peerId)")
        }
    }
}
