//
//  Connection.swift
//  BotDrive
//
//  Created by Brian Smith on 5/8/21.
//

import Foundation

public class Connection: ObservableObject {
    @Published public var server: String
    @Published public var port: Int
    @Published public var path: String
    @Published public var isConnected: Bool
        
    public init(server: String = "", port: Int = 8554, path: String = "", isConnected: Bool = false) {
        self.server = server
        self.port = port
        self.path = path
        self.isConnected = isConnected
    }
}
