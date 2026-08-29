import CommitmentProtection

struct AccountRowActionPresentation: Equatable {
    enum ConnectionAction: Equatable {
        case reconnect
        case disconnect
        case connecting
    }

    let connectionAction: ConnectionAction
    let showsRemoveAccountAction: Bool

    static func make(
        connectionState: ConnectionState,
        isConnectingThisAccount: Bool
    ) -> Self {
        if isConnectingThisAccount {
            return Self(
                connectionAction: .connecting,
                showsRemoveAccountAction: false
            )
        }

        if connectionState == .reconnectRequired {
            return Self(
                connectionAction: .reconnect,
                showsRemoveAccountAction: true
            )
        }

        return Self(
            connectionAction: .disconnect,
            showsRemoveAccountAction: true
        )
    }
}
