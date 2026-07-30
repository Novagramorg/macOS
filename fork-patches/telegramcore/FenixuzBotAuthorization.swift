import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi
import MtProtoKit

// Bot-token login (Novagram / Fenixuz fork). Port of the iOS fork's
// submodules/TelegramCore/Sources/FenixuzBotAuthorization.swift.
//
// This lives inside TelegramCore rather than the app target because the completion
// helpers it reuses — switchToAuthorizedAccount, storeFutureLoginToken,
// initializedAppSettingsAfterLogin and TelegramUser(user:) — are all internal to this
// module. Reimplementing them app-side would fork the account-record logic away from
// upstream with no compile-time link, so a future upstream change would silently write
// a malformed record for bot logins only.
//
// Equatable is required here (the iOS copy doesn't need it) because AuthController.State
// on macOS is Equatable and holds this error as an optional.
public enum ImportBotAuthorizationError: Equatable {
    case invalidToken
    case limitExceeded
    case generic
}

// auth.importBotAuthorization is atomic — no code and no password step — so this mirrors
// only the tail of the phone flow and reuses its exact completion helpers instead of
// adding a new UnauthorizedAccountStateContents case.
public func importBotAuthorization(accountManager: AccountManager<TelegramAccountManagerTypes>, account: UnauthorizedAccount, apiId: Int32, apiHash: String, botToken: String) -> Signal<Void, ImportBotAuthorizationError> {
    let performRequest: (UnauthorizedAccount) -> Signal<Api.auth.Authorization, MTRpcError> = { acc in
        return acc.network.request(Api.functions.auth.importBotAuthorization(flags: 0, apiId: apiId, apiHash: apiHash, botAuthToken: botToken), automaticFloodWait: false)
    }

    return performRequest(account)
    |> map { authorization -> (Api.auth.Authorization, UnauthorizedAccount) in
        return (authorization, account)
    }
    |> `catch` { error -> Signal<(Api.auth.Authorization, UnauthorizedAccount), MTRpcError> in
        // A bot lives on one DC. If the request hit the wrong one the server answers
        // USER_MIGRATE_/NETWORK_MIGRATE_/PHONE_MIGRATE_<dc>: move the account to that DC and
        // retry there (same shape as sendAuthorizationCode in Authorization.swift). Parsed with
        // if-let rather than upstream's force-unwrap so a malformed description can't crash.
        let desc = error.errorDescription ?? ""
        if let range = desc.range(of: "MIGRATE_"), let updatedMasterDatacenterId = Int32(desc[range.upperBound...]) {
            return account.changedMasterDatacenterId(accountManager: accountManager, masterDatacenterId: updatedMasterDatacenterId)
            |> mapToSignalPromotingError { updatedAccount -> Signal<(Api.auth.Authorization, UnauthorizedAccount), MTRpcError> in
                return performRequest(updatedAccount)
                |> map { authorization -> (Api.auth.Authorization, UnauthorizedAccount) in
                    return (authorization, updatedAccount)
                }
            }
        } else {
            return .fail(error)
        }
    }
    |> mapError { error -> ImportBotAuthorizationError in
        let desc = error.errorDescription ?? ""
        if desc == "ACCESS_TOKEN_INVALID" || desc == "ACCESS_TOKEN_EXPIRED" {
            return .invalidToken
        } else if desc.hasPrefix("FLOOD_WAIT") {
            return .limitExceeded
        } else {
            return .generic
        }
    }
    |> mapToSignal { resultAndAccount -> Signal<Void, ImportBotAuthorizationError> in
        let (result, resolvedAccount) = resultAndAccount
        return resolvedAccount.postbox.transaction { transaction -> Signal<Void, ImportBotAuthorizationError> in
            switch result {
            case let .authorization(_, _, _, futureAuthToken, apiUser):
                if let futureAuthToken = futureAuthToken {
                    storeFutureLoginToken(accountManager: accountManager, token: futureAuthToken.makeData())
                }

                let user = TelegramUser(user: apiUser)
                let state = AuthorizedAccountState(isTestingEnvironment: resolvedAccount.testingEnvironment, masterDatacenterId: resolvedAccount.masterDatacenterId, peerId: user.id, state: nil, invalidatedChannels: [])
                initializedAppSettingsAfterLogin(transaction: transaction, appVersion: resolvedAccount.networkArguments.appVersion, syncContacts: false)
                transaction.setState(state)
                // Mark this as a bot session so the managed hole operations stop retrying the
                // user-only RPCs a bot can't call. See FenixuzBotSession.swift.
                setFenixuzBotSession(transaction: transaction, isBot: true)

                return accountManager.transaction { transaction in
                    switchToAuthorizedAccount(transaction: transaction, account: resolvedAccount, isSupportUser: false)
                }
                |> castError(ImportBotAuthorizationError.self)
            case .authorizationSignUpRequired:
                // Bots have no signup step; the server should never send this for a bot token.
                return .fail(.generic)
            }
        }
        |> castError(ImportBotAuthorizationError.self)
        |> switchToLatest
    }
}
