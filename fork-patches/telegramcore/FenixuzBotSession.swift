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
// Only the hooks that are live on iOS are ported. iOS also defines force-chat-inclusion,
// DM-read-state seeding and folder-filter helpers, but nothing calls them there and the iOS
// build works without them — so they are deliberately not carried over as dead code.

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
